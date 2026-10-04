import Foundation
import Synchronization

/// A password or a Steam Guard code, held in memory for one sign-in and typed
/// into steamcmd's terminal at its prompt. It is never written anywhere else:
/// it is not `Codable`, and it prints as dots, so it cannot reach a log or a
/// file by accident. One with a line break in it is refused, since the part
/// after the break would be typed as a console command.
public struct SteamSecret: Sendable, CustomStringConvertible, CustomDebugStringConvertible {
    fileprivate let text: String

    public init?(_ text: String) {
        guard !text.isEmpty, !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        self.text = text
    }

    public var description: String { "••••" }
    public var debugDescription: String { "••••" }

    /// Whether it is this text, without handing its own out.
    public func matches(_ other: String) -> Bool {
        text == other
    }
}

/// Valve's steamcmd, driven through its console over a pseudo-terminal (record
/// 0009). The account name, the password and a Steam Guard code are typed at
/// its prompts and never passed as arguments, which `ps` would show; only
/// `+@sSteamCmdForcePlatformType windows` is, so that a Workshop item comes
/// with the files Wallpaper Engine itself would get.
///
/// One job at a time: steamcmd keeps its login and its downloads in Steam's own
/// folder, which two of them at once would both write.
public struct SteamCmd: Sendable {
    public struct Limits: Sendable {
        /// A sign-in waits on the user: a code, or an approval in the Steam Mobile app.
        public var signIn: Duration
        public var download: Duration
        /// Anything else: setting up, signing out.
        public var other: Duration
        /// How long steamcmd has to go once it has answered.
        public var leaving: Duration

        public init(
            signIn: Duration = .seconds(10 * 60),
            download: Duration = .seconds(60 * 60),
            other: Duration = .seconds(5 * 60),
            leaving: Duration = .seconds(20)
        ) {
            self.signIn = signIn
            self.download = download
            self.other = other
            self.leaving = leaving
        }

        func limit(for job: SteamJob) -> Duration {
            switch job {
            case .signIn: signIn
            case .download: download
            case .signOut, .update: other
            }
        }
    }

    /// Only this: Wallpaper Engine is a Windows program, and its items are fetched as Windows would.
    public static let arguments = ["+@sSteamCmdForcePlatformType", "windows"]

    public let executable: URL
    public let environment: [String: String]
    public var limits: Limits
    /// Whether steamcmd may run, asked before every start of it, the one after
    /// it updated itself included: `SteamCmdTool.check`, Valve's signature on it
    /// and on everything in its folder.
    public let check: @Sendable () throws(WorkshopError) -> Void

    /// Valve's steamcmd where `tool` keeps it, checked by `tool` before every start.
    public init(tool: SteamCmdTool, home: URL, limits: Limits = Limits()) {
        self.init(executable: tool.executable, home: home, check: { () throws(WorkshopError) in try tool.check() }, limits: limits)
    }

    /// `home` is where steamcmd keeps its login and puts what it downloads
    /// (`Library/Application Support/Steam` inside it). `extra` is added to the
    /// environment, for tests.
    public init(
        executable: URL, home: URL, check: @escaping @Sendable () throws(WorkshopError) -> Void,
        extra: [String: String] = [:], limits: Limits = Limits()
    ) {
        let folder = executable.deletingLastPathComponent().path
        let inherited = ProcessInfo.processInfo.environment
        var environment = [
            "HOME": home.path,
            "PATH": "/usr/bin:/bin:/usr/sbin:/sbin",
            // What steamcmd.sh sets, so that it finds the libraries beside it.
            "DYLD_LIBRARY_PATH": folder,
            "DYLD_FRAMEWORK_PATH": folder,
        ]
        for name in ["USER", "LOGNAME", "TMPDIR", "LANG"] {
            environment[name] = inherited[name]
        }
        self.executable = executable
        self.environment = environment.merging(extra) { _, new in new }
        self.limits = limits
        self.check = check
    }

    /// Runs one job to its end. A download and a sign-out use the saved login
    /// and never type a password. A sign-in types `password` at its prompt and
    /// asks `code` for each Steam Guard code; answering nil cancels it.
    /// `progress` hears how it is getting on, and `line` every line steamcmd
    /// prints (nothing typed is among them). Cancelling the task stops steamcmd.
    public func run(
        _ job: SteamJob,
        password: SteamSecret? = nil,
        // No async closure as a default argument: Swift 6.2 miscompiles one (see `Importer.init`).
        code: (@Sendable (SteamGuard, _ again: Bool) async -> SteamSecret?)? = nil,
        progress: @escaping @Sendable (SteamProgress) -> Void = { _ in },
        line: @escaping @Sendable (String) -> Void = { _ in }
    ) async throws -> SteamOutcome {
        var conversation = SteamConversation(job: job)
        while true {
            // Before every start: steamcmd that has just updated itself is a different program.
            try check()
            let process: PseudoTerminalProcess
            do {
                process = try PseudoTerminalProcess.start(
                    executable: executable, arguments: Self.arguments, environment: environment,
                    directory: executable.deletingLastPathComponent()
                )
            } catch .wrongArchitecture {
                throw WorkshopError.rosettaMissing
            } catch {
                throw WorkshopError.toolNotStarted
            }
            let session = Session(process: process, password: password, code: code ?? { _, _ in nil }, progress: progress, line: line)
            let ending = try await session.run(&conversation, limit: limits.limit(for: job), leaving: limits.leaving)
            switch ending {
            case .restart:
                continue
            case .finished(let result):
                return try result.get()
            }
        }
    }
}

/// One run of steamcmd: its output read into lines, the lines into effects, the effects carried out.
private struct Session: Sendable {
    enum Ending: Sendable {
        case finished(Result<SteamOutcome, WorkshopError>)
        /// steamcmd updated itself and must be started again.
        case restart
    }

    let process: PseudoTerminalProcess
    let password: SteamSecret?
    let code: @Sendable (SteamGuard, Bool) async -> SteamSecret?
    let progress: @Sendable (SteamProgress) -> Void
    let line: @Sendable (String) -> Void

    /// What the run has come to so far.
    private struct Progress {
        var result: Result<SteamOutcome, WorkshopError>?
        var restart = false
        var leavingWatch: Task<Void, Never>?
    }

    func run(_ conversation: inout SteamConversation, limit: Duration, leaving: Duration) async throws -> Ending {
        let timedOut = Flag()
        let watch = Task { [process] in
            try await Task.sleep(for: limit)
            timedOut.set()
            process.kill()
        }
        defer { watch.cancel() }

        var transcript = SteamTranscript()
        var sofar = Progress()
        defer { sofar.leavingWatch?.cancel() }

        try await withTaskCancellationHandler {
            for await event in process.events {
                var effects: [SteamConversation.Effect] = []
                switch event {
                case .output(let data):
                    for read in transcript.read(data, lines: line) {
                        effects += conversation.read(read)
                    }
                case .exited where timedOut.isSet && sofar.result == nil:
                    // Stopped for taking too long: that is the answer, not the signal that stopped it.
                    sofar.result = .failure(.timedOut)
                case .exited(let status):
                    effects = conversation.exited(status: status)
                }
                for effect in effects {
                    try await carry(effect, &sofar, leaving: leaving)
                }
            }
        } onCancel: {
            process.kill()
        }
        try Task.checkCancellation()
        if sofar.restart { return .restart }
        if let result = sofar.result { return .finished(result) }
        return .finished(.failure(timedOut.isSet ? .timedOut : .noAnswer))
    }

    /// Carries out one of the conversation's effects.
    private func carry(_ effect: SteamConversation.Effect, _ sofar: inout Progress, leaving: Duration) async throws {
        switch effect {
        case .type(let command):
            process.type(command + "\n")
        case .typePassword:
            // A sign-in without a password has nothing to type: it cannot go on.
            guard let password else {
                sofar.result = .failure(.signInNeeded)
                process.kill()
                return
            }
            process.type(password.text + "\n")
        case .askForCode(let kind, let again):
            guard let answer = await code(kind, again) else {
                process.kill()
                throw CancellationError()
            }
            process.type(answer.text + "\n")
        case .report(let step):
            progress(step)
        case .finish(let answer):
            sofar.result = sofar.result ?? answer
            // It has answered; it has a little while to go by itself.
            sofar.leavingWatch = Task { [process] in
                try? await Task.sleep(for: leaving)
                if !Task.isCancelled { process.kill() }
            }
        case .stop:
            process.terminate()
        case .restart:
            sofar.restart = true
        }
    }
}

/// Set once, read from anywhere.
private final class Flag: Sendable {
    private let value = Atomic(false)

    var isSet: Bool { value.load(ordering: .relaxed) }

    func set() {
        value.store(true, ordering: .relaxed)
    }
}
