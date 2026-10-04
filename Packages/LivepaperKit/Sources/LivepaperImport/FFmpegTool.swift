import Foundation
import Synchronization

public enum FFmpegError: Error, Equatable, Sendable {
    case launchFailed(String)
    /// ffmpeg gave up. The message is the last thing it said.
    case failed(status: Int32, message: String)
    case timeLimitExceeded
    case sizeLimitExceeded
}

/// The ffmpeg helper: converts a file AVFoundation cannot open
/// into one it can, once, at import. It never runs at playback time.
///
/// The files it parses are untrusted, so it runs as a separate process with a
/// fixed argument list, an empty environment and nothing on its standard
/// input, against a time limit and a size limit (ffmpeg's own `-fs` is not
/// used: it stops quietly and reports success with half a file). The helper itself is built
/// without network support (`Helpers/ffmpeg/build.sh`).
public struct FFmpegTool: Equatable, Sendable {
    public struct Limits: Equatable, Sendable {
        public var time: Duration
        public var outputBytes: Int64

        public init(time: Duration = .seconds(60 * 60), outputBytes: Int64 = 32 << 30) {
            self.time = time
            self.outputBytes = outputBytes
        }
    }

    public let executable: URL
    public var limits: Limits

    public init(executable: URL, limits: Limits = Limits()) {
        self.executable = executable
        self.limits = limits
    }

    /// The helper to use: a replacement the user points at, when it is there
    /// and can be run, otherwise the one bundled with the app. Being able to
    /// swap the binary is what the LGPL asks for.
    public static func locate(replacement: URL?, bundled: URL?) -> FFmpegTool? {
        [replacement, bundled]
            .compactMap(\.self)
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
            .map { FFmpegTool(executable: $0) }
    }

    /// Everything but the two paths is fixed. The paths are absolute, so
    /// neither can be read as an option or as a protocol.
    public static func arguments(source: URL, destination: URL) -> [String] {
        [
            "-nostdin", "-hide_banner", "-nostats", "-loglevel", "info", "-y",
            "-protocol_whitelist", "file,pipe",
            "-i", source.absoluteURL.path,
            // The first video track and the first audio track if there is one. No subtitles, data or tags.
            "-map", "0:v:0", "-map", "0:a:0?", "-sn", "-dn", "-map_metadata", "-1",
            // No B-frames and a constant rate, so that what comes out can be remuxed rather than encoded twice.
            // `-allow_sw` lets a Mac with no free hardware encoder (a CI runner) still convert.
            "-c:v", "hevc_videotoolbox", "-allow_sw", "1", "-tag:v", "hvc1", "-q:v", "65", "-pix_fmt", "yuv420p", "-bf", "0",
            "-fps_mode", "cfr",
            "-c:a", "aac", "-b:a", "192k",
            "-progress", "pipe:1",
            "-f", "mov", destination.absoluteURL.path,
        ]
    }

    /// Converts the source file to an HEVC QuickTime movie at `destination`.
    /// Progress is 0 to 1, or nil when ffmpeg could not tell how long the file
    /// is. Whatever goes wrong, a cancel included, the process is gone and no file is left.
    @concurrent
    public func convert(_ source: URL, to destination: URL, progress: @escaping @Sendable (Double?) -> Void) async throws {
        do {
            try await run(source, to: destination, progress: progress)
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    /// Nothing from this process's environment, nothing to read, and only the fixed arguments.
    private func sealedProcess(converting source: URL, to destination: URL) -> Process {
        let process = Process()
        process.executableURL = executable
        process.arguments = Self.arguments(source: source, destination: destination)
        process.environment = [:]
        process.currentDirectoryURL = destination.deletingLastPathComponent()
        process.standardInput = FileHandle.nullDevice
        return process
    }

    private func run(_ source: URL, to destination: URL, progress: @escaping @Sendable (Double?) -> Void) async throws {
        let process = sealedProcess(converting: source, to: destination)
        let said = Mutex(Transcript())
        let progressRead = follow(process, \.standardOutput) { data in said.withLock { $0.readProgress(data) }.forEach(progress) }
        let logRead = follow(process, \.standardError) { data in said.withLock { $0.readLog(data) } }

        let running = RunningProcess(process)
        let ending = try await withThrowingTaskGroup(of: Ending.self) { group in
            group.addTask {
                try await running.exit()
                return .exited
            }
            group.addTask { [limits] in
                await running.watch(destination, limits: limits)
            }
            // The exit ends it. A limit only stops the process, and the exit follows.
            defer { group.cancelAll() }
            var limit: FFmpegError?
            while let ending = try await group.next() {
                switch ending {
                // The exit a limit caused can come before the watch says which limit it was.
                case .exited: return (limit ?? running.limitPassed).map(Ending.stopped) ?? .exited
                case .stopped(let error): limit = error
                case .watchEnded: break
                }
            }
            return .exited
        }

        try Task.checkCancellation()
        if case .stopped(let limit) = ending { throw limit }
        // It exited by itself, so its ends of the pipes are closed and the two readers are at their last lines.
        // Not for ever, though: a replacement that left a child behind would hold them open.
        try await onOwnThread { _ in
            for read in [progressRead, logRead] { _ = read.wait(timeout: .now() + 2) }
        }

        let status = process.terminationStatus
        guard status == 0, process.terminationReason == .exit else {
            throw FFmpegError.failed(status: status, message: said.withLock { $0.lastLine })
        }
        // A helper that finishes between two looks of the watch is measured here.
        guard let size = Self.size(of: destination) else { throw FFmpegError.failed(status: 0, message: "no output was written") }
        guard size <= limits.outputBytes else { throw FFmpegError.sizeLimitExceeded }
    }

    fileprivate enum Ending: Sendable {
        case exited
        case stopped(FFmpegError)
        case watchEnded
    }

    fileprivate static func size(of file: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value
    }

    /// Reads one of the process's outputs on a thread of its own until it
    /// closes, in order, and signals when it has. Reading blocks, and Swift's
    /// own threads are not for blocking on (`onOwnThread`).
    private func follow(
        _ process: Process, _ stream: ReferenceWritableKeyPath<Process, Any?>, _ consume: @escaping @Sendable (Data) -> Void
    ) -> DispatchSemaphore {
        let pipe = Pipe()
        process[keyPath: stream] = pipe
        let closed = DispatchSemaphore(value: 0)
        let reading = Unchecked(pipe.fileHandleForReading)
        Thread.detachNewThread {
            while case let data = reading.value.availableData, !data.isEmpty { consume(data) }
            closed.signal()
        }
        return closed
    }
}

/// A process that can be waited for, stopped from another task, and that is
/// stopped when the task waiting for it is cancelled.
private final class RunningProcess: @unchecked Sendable {
    // Process is not Sendable. What is used across tasks here (run, terminate, the
    // identifier and isRunning) is safe to call from any thread.
    private let process: Process
    /// The limit the watch stopped the process for, set before it is stopped.
    private let passed = Mutex<FFmpegError?>(nil)

    init(_ process: Process) {
        self.process = process
    }

    var limitPassed: FFmpegError? { passed.withLock { $0 } }

    func exit() async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                process.terminationHandler = { _ in continuation.resume() }
                do {
                    try process.run()
                    // A cancel that came before there was anything to stop.
                    if Task.isCancelled { stop() }
                } catch {
                    process.terminationHandler = nil
                    continuation.resume(throwing: FFmpegError.launchFailed(error.localizedDescription))
                }
            }
        } onCancel: {
            stop()
        }
    }

    /// Asks, then insists: a helper stuck on a hostile file may not be listening.
    func stop() {
        guard process.isRunning else { return }
        process.terminate()
        let identifier = process.processIdentifier
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [process] in
            if process.isRunning { kill(identifier, SIGKILL) }
        }
    }

    /// Stops the process when it passes a limit, and says which. Ends quietly once cancelled.
    func watch(_ destination: URL, limits: FFmpegTool.Limits) async -> FFmpegTool.Ending {
        let clock = ContinuousClock()
        let deadline = clock.now + limits.time
        while !Task.isCancelled {
            let size = FFmpegTool.size(of: destination) ?? 0
            let limit: FFmpegError? = size > limits.outputBytes ? .sizeLimitExceeded : clock.now >= deadline ? .timeLimitExceeded : nil
            if let limit {
                passed.withLock { $0 = limit }
                stop()
                return .stopped(limit)
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return .watchEnded
    }
}

/// What ffmpeg writes while it runs: `-progress` blocks on its standard
/// output, its log on its standard error. Kept as bytes until a line is
/// whole, because a read can end in the middle of a character.
private struct Transcript {
    private var progress = Data()
    private var log = Data()
    private var duration: Double?

    var lastLine: String {
        Self.lines(of: log).last { !$0.isEmpty } ?? ""
    }

    /// The fractions that the complete lines in `data` amount to.
    mutating func readProgress(_ data: Data) -> [Double?] {
        progress += data
        guard let end = progress.lastIndex(of: Self.newline) else { return [] }
        let lines = Self.lines(of: progress[..<end])
        progress = Data(progress[progress.index(after: end)...])

        return lines.compactMap { line -> Double?? in
            guard line.hasPrefix("out_time_us="), let microseconds = Double(line.dropFirst("out_time_us=".count)) else { return nil }
            guard let duration, duration > 0 else { return .some(nil) }
            return min(1, max(0, microseconds / 1_000_000 / duration))
        }
    }

    mutating func readLog(_ data: Data) {
        log += data
        if duration == nil { duration = Self.lines(of: log).lazy.compactMap(Self.announcedDuration).first }
        // Only the end of the log is ever wanted, and a hostile file can make ffmpeg say a great deal.
        if log.count > 16_384 { log = Data(log.suffix(8_192)) }
    }

    private static let newline = UInt8(ascii: "\n")

    private static func lines(of data: Data) -> [String] {
        data.split(separator: newline).map { line in
            // Latin-1 reads any bytes, so a file name in some other encoding still shows up in the message.
            (String(bytes: line, encoding: .utf8) ?? String(bytes: line, encoding: .isoLatin1) ?? "").trimmingCharacters(in: .whitespaces)
        }
    }

    /// `Duration: 00:01:02.50` in the header ffmpeg prints about its input.
    private static func announcedDuration(in line: String) -> Double? {
        guard let match = line.firstMatch(of: /Duration: (\d+):(\d\d):(\d\d(?:\.\d+)?)/) else { return nil }
        guard let hours = Double(match.1), let minutes = Double(match.2), let seconds = Double(match.3) else { return nil }
        return hours * 3600 + minutes * 60 + seconds
    }
}
