import Foundation

public enum ShaderToolError: Error, Equatable, Sendable {
    /// The tool could not be started at all: nothing about the shader is known.
    case launchFailed(tool: String, message: String)
    /// A run went on past `ShaderTools.timeLimit` and was stopped.
    case timeLimitExceeded(tool: String)
    /// A run wrote more than `ShaderTools.outputLimit` and was stopped.
    case outputLimitExceeded(tool: String)
}

extension ShaderToolError: CustomStringConvertible {
    public var description: String {
        switch self {
        case .launchFailed(let tool, let message): "\(tool) could not be started: \(message)"
        case .timeLimitExceeded(let tool): "\(tool) took too long and was stopped"
        case .outputLimitExceeded(let tool): "\(tool) wrote too much and was stopped"
        }
    }

    /// A limit the shader drove a tool past, as against a tool that could not
    /// be run at all. A run that took too long says as much about a busy
    /// machine as about the shader, so it is tried again another time.
    var isAboutTheShader: Bool {
        if case .outputLimitExceeded = self { true } else { false }
    }
}

/// The shader tools: glslang, which preprocesses a scene's GLSL
/// and compiles it to SPIR-V, and SPIRV-Cross, which turns SPIR-V into Metal
/// Shading Language. They run at import, and in the app when a scene is
/// prepared again, never in the extension.
///
/// The shaders come from Workshop items, so every run is a separate process
/// with a fixed argument list, an empty environment, nothing on its standard
/// input and its outputs going to files, stopped when it passes a time limit
/// or an output limit, or when the task waiting for it is cancelled. A crash
/// or a hang ends that process, never the app.
public struct ShaderTools: Equatable, Sendable {
    public let glslang: URL
    public let spirvCross: URL
    /// How long one run of either tool may take. A program is six runs.
    public var timeLimit: Duration
    /// How many bytes one run may write to each of its outputs.
    public var outputLimit: Int

    public init(glslang: URL, spirvCross: URL, timeLimit: Duration = .seconds(5), outputLimit: Int = 16 << 20) {
        self.glslang = glslang
        self.spirvCross = spirvCross
        self.timeLimit = timeLimit
        self.outputLimit = outputLimit
    }

    /// The tools bundled next to the app's executable, when both are there and
    /// can be run. Unlike ffmpeg's licence, theirs ask for no replacement route.
    public static func locate(bundled glslang: URL?, _ spirvCross: URL?) -> ShaderTools? {
        guard let glslang, let spirvCross else { return nil }
        let runnable = [glslang, spirvCross].allSatisfy { FileManager.default.isExecutableFile(atPath: $0.path) }
        return runnable ? ShaderTools(glslang: glslang, spirvCross: spirvCross) : nil
    }

    /// The versions `Helpers/shader-tools/build.sh` builds. The tests hold
    /// them to what the binaries say (`glslang --version`, `spirv-cross --revision`).
    public static let glslangVersion = "16.6.0"
    public static let spirvCrossVersion = "vulkan-sdk-1.4.357.0"

    /// For `ScenePrograms.tools`, the record of what translated a scene.
    public var version: String {
        "glslang \(Self.glslangVersion), SPIRV-Cross \(Self.spirvCrossVersion)"
    }
}

/// What one run of a tool left: how it ended, and what it wrote.
struct ToolRun {
    var status: Int32
    var output: String
    var errors: String

    var succeeded: Bool { status == 0 }
    /// Both outputs, for a message: glslang puts its errors on either.
    var said: String { errors + "\n" + output }
}

extension ShaderTools {
    /// Runs one tool in `folder`, which its paths are relative to, and waits for
    /// it. Blocks, so only on a thread of its own (`onOwnThread`). Throws
    /// `ShaderToolError` when it cannot start or is stopped at a limit, and
    /// `CancellationError` when `cancellation` says so; the process is gone either way.
    func run(_ tool: URL, _ arguments: [String], in folder: URL, cancellation: Cancellation) throws -> ToolRun {
        let name = tool.lastPathComponent
        let output = folder.appending(path: "\(name).out", directoryHint: .notDirectory)
        let errors = folder.appending(path: "\(name).err", directoryHint: .notDirectory)
        let files = FileManager.default
        guard files.createFile(atPath: output.path, contents: nil), files.createFile(atPath: errors.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let outputHandle = try FileHandle(forWritingTo: output)
        let errorsHandle = try FileHandle(forWritingTo: errors)
        defer {
            try? outputHandle.close()
            try? errorsHandle.close()
        }

        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        process.environment = [:]
        process.currentDirectoryURL = folder
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outputHandle
        process.standardError = errorsHandle
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            throw ShaderToolError.launchFailed(tool: name, message: error.localizedDescription)
        }

        // The time limit is the tool's own time: a Mac asleep in the middle of a run does not use it up.
        let clock = SuspendingClock()
        let deadline = clock.now + timeLimit
        while exited.wait(timeout: .now() + .milliseconds(25)) == .timedOut {
            let stoppedBy: (any Error)? = if cancellation.isCancelled {
                CancellationError()
            } else if clock.now >= deadline {
                ShaderToolError.timeLimitExceeded(tool: name)
            } else if [output, errors].contains(where: { Self.size(of: $0) > outputLimit }) {
                ShaderToolError.outputLimitExceeded(tool: name)
            } else {
                nil
            }
            if let stoppedBy {
                Self.stop(process, exited: exited)
                throw stoppedBy
            }
        }
        return ToolRun(status: process.terminationStatus, output: Self.text(of: output), errors: Self.text(of: errors))
    }

    /// Asks, then insists, and waits for it to be gone, so that nothing writes
    /// into the work folder once it is removed.
    private static func stop(_ process: Process, exited: DispatchSemaphore) {
        guard process.isRunning else { return }
        process.terminate()
        if exited.wait(timeout: .now() + .seconds(1)) == .timedOut {
            kill(process.processIdentifier, SIGKILL)
            _ = exited.wait(timeout: .now() + .seconds(5))
        }
    }

    private static func size(of file: URL) -> Int {
        (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.intValue ?? 0
    }

    /// Latin-1 reads any bytes, so a message in some other encoding still shows up.
    private static func text(of file: URL) -> String {
        guard let data = try? Data(contentsOf: file) else { return "" }
        return String(bytes: data, encoding: .utf8) ?? String(bytes: data, encoding: .isoLatin1) ?? ""
    }
}
