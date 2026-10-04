import Foundation
import Testing
import LivepaperImport

/// How the shader tools are found and run, against stand-ins: shell scripts
/// that behave as glslang might on a bad day. The real tools are exercised by
/// the translator's tests.
struct ShaderToolsTests {
    let folder: TemporaryFolder

    init() throws {
        folder = try TemporaryFolder()
    }

    /// An executable script at `path`.
    @discardableResult
    func script(_ body: String, at path: String) throws -> URL {
        let url = try folder.write("#!/bin/sh\n\(body)\n", to: path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    /// Stand-in tools: `glslang` runs `body`, and `spirv-cross` is never reached.
    func tools(glslang body: String, timeLimit: Duration = .seconds(5), outputLimit: Int = 16 << 20) throws -> ShaderTools {
        ShaderTools(
            glslang: try script(body, at: "tools/glslang"), spirvCross: try script("exit 1", at: "tools/spirv-cross"),
            timeLimit: timeLimit, outputLimit: outputLimit
        )
    }

    func translate(with tools: ShaderTools) async throws {
        _ = try await ShaderTranslator(tools: tools).translate(vertex: "void main() {}", fragment: "void main() {}", defines: [])
    }

    /// Whether a process of this number is still there.
    func isRunning(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0
    }

    func recordedPID() throws -> pid_t {
        try #require(pid_t(String(contentsOf: folder.file("pid"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    // MARK: Which binaries

    @Test func `both tools are found when both are there and can be run`() throws {
        let glslang = try script("exit 0", at: "bundled/glslang")
        let spirvCross = try script("exit 0", at: "bundled/spirv-cross")

        let tools = try #require(ShaderTools.locate(bundled: glslang, spirvCross))
        #expect(tools.glslang == glslang && tools.spirvCross == spirvCross)
    }

    @Test func `a tool that is missing or cannot be run means there are none`() throws {
        let glslang = try script("exit 0", at: "bundled/glslang")
        let notExecutable = try folder.write("not a program", to: "bundled/spirv-cross")

        #expect(ShaderTools.locate(bundled: glslang, notExecutable) == nil)
        #expect(ShaderTools.locate(bundled: glslang, folder.file("gone/spirv-cross")) == nil)
        #expect(ShaderTools.locate(bundled: nil, glslang) == nil)
        #expect(ShaderTools.locate(bundled: glslang, nil) == nil)
    }

    // MARK: How they are run

    @Test func `a tool is given a fixed argument list, an empty environment and nothing to read`() async throws {
        let record = folder.file("record.txt")
        let tools = try tools(glslang: """
            # The shell sets these three itself. Anything else would have come from the importer.
            { printf '%s\\n' "$@"; echo "env:"; env | grep -Ev '^(PWD|_|SHLVL)='; echo "stdin:"; cat; } > '\(record.path)'
            echo "ERROR: in.vert:1: stand-in says no"
            exit 2
            """)

        await #expect(throws: ShaderTranslationFailure(stage: .vertex, step: .preprocess, message: "ERROR: line 1: stand-in says no")) {
            try await translate(with: tools)
        }

        #expect(try String(contentsOf: record, encoding: .utf8) == "-E\n-Iinclude\nin.vert\nenv:\nstdin:\n")
    }

    @Test func `a tool that runs past its time limit is stopped`() async throws {
        let tools = try tools(glslang: "echo $$ > '\(folder.file("pid").path)'\nexec sleep 30", timeLimit: .seconds(1))
        let clock = ContinuousClock()
        let start = clock.now

        await #expect(throws: ShaderToolError.timeLimitExceeded(tool: "glslang")) { try await translate(with: tools) }

        // Well short of the stand-in's 30 s; loose enough for a busy CI machine (4.5 s seen).
        #expect(clock.now - start < .seconds(20))
        // A machine busy enough may stop the stand-in before it has said who it is; then there is nothing to look for.
        if let pid = try? recordedPID() {
            #expect(!isRunning(pid), "the process is gone")
        }
    }

    @Test func `a tool that writes without end is stopped`() async throws {
        let tools = try tools(glslang: "exec yes 'a long line of preprocessed text'", outputLimit: 1 << 20)

        await #expect(throws: ShaderToolError.outputLimitExceeded(tool: "glslang")) { try await translate(with: tools) }
    }

    @Test func `cancelling the translation stops the tool`() async throws {
        let tools = try tools(glslang: "echo $$ > '\(folder.file("pid").path)'\nexec sleep 30")
        let pidFile = folder.file("pid")
        let translation = Task { try await translate(with: tools) }
        // Once the stand-in is running.
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: pidFile.path), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }

        translation.cancel()

        await #expect(throws: CancellationError.self) { try await translation.value }
        #expect(!isRunning(try recordedPID()), "the process is gone")
    }

    @Test func `a tool that cannot be started says so`() async throws {
        let tools = ShaderTools(glslang: folder.file("gone/glslang"), spirvCross: folder.file("gone/spirv-cross"))

        let error = await #expect(throws: ShaderToolError.self) { try await translate(with: tools) }

        guard case .launchFailed(let tool, _) = error else {
            Issue.record("not a launch failure: \(String(describing: error))")
            return
        }
        #expect(tool == "glslang")
    }

    @Test func `the work folder is removed afterwards`() async throws {
        let record = folder.file("cwd.txt")
        let tools = try tools(glslang: "pwd > '\(record.path)'\nexit 2")

        _ = try? await translate(with: tools)

        let workFolder = try String(contentsOf: record, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!workFolder.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: workFolder))
    }

    // MARK: The real tools

    @Test(.enabled(if: ShaderToolsHelper.shouldRun))
    func `the versions recorded are the ones the tools report`() throws {
        let tools = try ShaderToolsHelper.required()

        #expect(try output(of: tools.glslang, ["--version"]).contains("glslang Khronos. \(ShaderTools.glslangVersion)"))
        #expect(try output(of: tools.spirvCross, ["--revision"]).contains("Git commit: \(ShaderTools.spirvCrossVersion) "))
        #expect(tools.version == "glslang \(ShaderTools.glslangVersion), SPIRV-Cross \(ShaderTools.spirvCrossVersion)")
    }

    private func output(of tool: URL, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        // spirv-cross prints its revision on its standard error.
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(bytes: data, encoding: .utf8) ?? ""
    }
}
