import Foundation
import LivepaperCore

/// One line the wallpaper extension logged, as `log show` gives it.
nonisolated struct ExtensionLogLine: Equatable, Sendable {
    /// As the log gives it, with its time zone: `2026-09-24 11:58:38.677991+0100`.
    var timestamp: String
    /// `Default`, `Info`, `Debug`, `Error` or `Fault`.
    var level: String
    var category: String
    var message: String

    var text: String { "\(timestamp) \(level) [\(category)] \(message)" }
}

/// The wallpaper extension's recent log lines, for the diagnostics report:
/// what `/usr/bin/log show` gives for the extension's subsystem over the last
/// ten minutes, the latest 200 at most, and its latest self-check line since
/// the Mac started, which it logs once at launch. No other process's lines
/// are asked for.
///
/// The lines are kept as the log gave them and only the report reads them,
/// through the report's `Redaction`: nothing else can take them out.
///
/// A plain user gets lines: on macOS 27.0, as the logged-in user and an
/// administrator, without `sudo`, `log show` gave the extension's lines. The
/// `log` tool refuses some commands to anyone not an administrator ("Must be
/// admin to run '<command>' command"); a standard account was not tried, and
/// what `log show` says then is kept as the report's problem. `OSLogStore.local()`
/// needed no entitlement there either, but `log show` is what is used.
nonisolated public struct ExtensionLogLines: Equatable, Sendable {
    /// How far back the lines go, in minutes.
    static let minutes = 10
    /// The most lines kept, the latest.
    static let limit = 200
    /// A query that takes longer is stopped: a report is not worth a hang.
    static let timeLimit: DispatchTimeInterval = .seconds(30)

    let lines: [ExtensionLogLine]
    /// The latest `bridge self-check: …` line since the Mac started.
    let selfCheck: ExtensionLogLine?
    /// Why the lines could not be read: what `log show` said, or how it failed.
    let problem: String?

    init(lines: [ExtensionLogLine], selfCheck: ExtensionLogLine?, problem: String?) {
        self.lines = lines
        self.selfCheck = selfCheck
        self.problem = problem
    }

    /// What the two queries wrote: the latest `limit` lines, and the latest self-check.
    init(recent: Data, selfChecks: Data) {
        let lines = Array(Self.entries(ndjson: recent).suffix(Self.limit))
        self.init(lines: lines, selfCheck: Self.entries(ndjson: selfChecks).last, problem: nil)
    }

    init(problem: String) {
        self.init(lines: [], selfCheck: nil, problem: problem)
    }

    /// Runs the two queries at once, each on a thread of its own: `log show`
    /// takes a second or two, the look back to the start longer the longer the Mac has run.
    public static func fetch(subsystem: String = WallpaperExtensionIdentity.logSubsystem) async -> ExtensionLogLines {
        async let recent = onOwnThread { run(recentArguments(subsystem: subsystem)) }
        async let selfChecks = onOwnThread { run(selfCheckArguments(subsystem: subsystem)) }
        switch await (recent, selfChecks) {
        case (.success(let recent), .success(let selfChecks)):
            return ExtensionLogLines(recent: recent, selfChecks: selfChecks)
        case (.failure(let problem), _), (_, .failure(let problem)):
            return ExtensionLogLines(problem: problem.words)
        }
    }

    // MARK: The queries

    static func recentArguments(subsystem: String) -> [String] {
        ["show", "--last", "\(minutes)m", "--style", "ndjson", "--predicate", "subsystem == \(quoted(subsystem))"]
    }

    static func selfCheckArguments(subsystem: String) -> [String] {
        let predicate = "subsystem == \(quoted(subsystem)) AND category == \"bridge\" AND eventMessage BEGINSWITH \"bridge self-check\""
        return ["show", "--last", "boot", "--style", "ndjson", "--predicate", predicate]
    }

    /// Each object `log show --style ndjson` wrote that carries a message; the
    /// trailer that counts them, and anything that is not an object, are left out.
    static func entries(ndjson: Data) -> [ExtensionLogLine] {
        let decoder = JSONDecoder()
        return ndjson.split(separator: UInt8(ascii: "\n")).compactMap { line in
            guard let entry = try? decoder.decode(Entry.self, from: Data(line)), let message = entry.eventMessage else { return nil }
            return ExtensionLogLine(
                timestamp: entry.timestamp ?? "", level: entry.messageType ?? "", category: entry.category ?? "", message: message
            )
        }
    }

    private struct Entry: Decodable {
        var timestamp: String?
        var messageType: String?
        var category: String?
        var eventMessage: String?
    }

    private struct Problem: Error {
        let words: String
    }

    /// Waits for `work` on a thread of its own, so that no thread of Swift's pool is held while it blocks.
    private static func onOwnThread<Value: Sendable>(_ work: @escaping @Sendable () -> Value) async -> Value {
        await withCheckedContinuation { continuation in
            Thread.detachNewThread { continuation.resume(returning: work()) }
        }
    }

    /// Runs `/usr/bin/log` and answers what it wrote. Its errors go to the same
    /// pipe, so that neither stream can fill and stall it, and are what a
    /// refusal answers.
    private static func run(_ arguments: [String]) -> Result<Data, Problem> {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/log")
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        do {
            try process.run()
        } catch {
            return .failure(Problem(words: "log show did not start: \(error.localizedDescription)"))
        }
        let stop = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeLimit, execute: stop)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        stop.cancel()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            let said = (String(bytes: data, encoding: .utf8) ?? "")
                .split(separator: "\n").filter { !$0.hasPrefix("{") }.joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            let status = process.terminationReason == .exit ? "exited with status \(process.terminationStatus)" : "was stopped"
            return .failure(Problem(words: said.isEmpty ? "log show \(status)" : "log show \(status): \(said)"))
        }
        return .success(data)
    }

    private static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
