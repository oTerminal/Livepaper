import Foundation
import LivepaperCore

// Commands from outside the app's windows: `livepaper://` links and the
// command socket. Each door's input becomes one `Command` (`EntryPoint`), and
// this runs it through the same actions the window's controls use, so the app
// stays the one writer. None imports: importing is done in the window alone.
// What is refused says why, in `CommandRefusal`'s words.

/// What a command can ask of the app beyond the model: its windows, and the
/// Steam account's name, which the diagnostics report leaves out.
struct CommandShell {
    var openLibrary: () -> Void
    var openSettings: () -> Void
    var steamAccount: () -> String?
}

extension AppModel {
    /// How long a command waits for the launch to read the library and the
    /// displays before it is refused: the tool waits for its reply with no
    /// time limit of its own.
    static let readyWait: Duration = .seconds(10)

    /// Runs a command from a door and answers it. A command that arrives
    /// before the launch has read the library and the displays waits for it,
    /// for `readyWait` at most.
    func perform(_ command: Command, from door: EntryPoint, shell: CommandShell) async -> CommandReply {
        AppLog.logger.notice("\(AppLog.command(command, from: door), privacy: .public)")
        guard await untilReady(within: Self.readyWait) else { return refuse(command, isQuitting ? .quitting : .stillStarting) }
        let reply: CommandReply
        do throws(CommandRefusal) {
            reply = try await run(command, shell: shell)
        } catch {
            return refuse(command, error)
        }
        AppLog.logger.notice("\(AppLog.commandDone(command), privacy: .public)")
        return reply
    }

    private func refuse(_ command: Command, _ refusal: CommandRefusal) -> CommandReply {
        AppLog.logger.notice("\(AppLog.commandRefused(command, refusal), privacy: .public)")
        return .refused(refusal)
    }

    /// `status`: the host, the displays by name and what each shows, the library, Pause All and mute.
    var statusReport: StatusReport {
        StatusReport(
            host: hostStatus,
            displays: Dictionary(displays.map { ($0.identity, $0.name) }) { first, _ in first },
            library: library,
            state: state,
            isPausedAll: isPausedAll
        )
    }

    /// Returns once the launch has read the library and the display sensor has
    /// named the displays, and at once after that, or at quit; answers whether
    /// it is ready. A door can hand over a command before either: a link that
    /// launched Livepaper arrives before the launch has finished. With a
    /// `limit`, it gives up after that long.
    @discardableResult
    func untilReady(within limit: Duration? = nil) async -> Bool {
        _ = await Polling.wait(until: { isReady || isQuitting }, every: .milliseconds(20), within: limit, clock: ContinuousClock())
        return isReady
    }

    private var isReady: Bool { isLaunched && areDisplaysKnown }

    private func run(_ command: Command, shell: CommandShell) async throws(CommandRefusal) -> CommandReply {
        // What reads, or opens a window, runs whatever the library's state.
        switch command {
        case .status: return .status(statusReport)
        case .diagnostics: return .diagnostics(await diagnosticsReport(steamAccount: shell.steamAccount()).text)
        case .library: shell.openLibrary()
        case .settings: shell.openSettings()
        case .set, .pause, .resume, .next, .mute, .unmute:
            if isQuitting { throw .quitting }
            if libraryProblem != nil { throw .libraryUnreadable }
            return try carryOut(command)
        }
        return .done(message: nil)
    }

    /// The commands that change something, through the actions the window's controls use.
    private func carryOut(_ command: Command) throws(CommandRefusal) -> CommandReply {
        switch command {
        case .set(let assignment, let target): try set(assignment, on: target)
        case .pause(let target): try setPaused(true, target)
        case .resume(let target): try setPaused(false, target)
        case .next(let target): return try moveOn(target)
        case .mute, .unmute: setMuted(command == .mute)
        case .status, .diagnostics, .library, .settings: break
        }
        return .done(message: nil)
    }

    private func set(_ assignment: Assignment, on target: DisplayTarget) throws(CommandRefusal) {
        try state.checking(assignment, in: library)
        switch target {
        case .all:
            setOnAllDisplays(assignment)
        case .display(let display):
            _ = try target.displays(connected: displays.map(\.identity))
            set(assignment, on: display)
        }
    }

    /// All is Pause All or Resume All; a display is that display's own pause.
    private func setPaused(_ isPaused: Bool, _ target: DisplayTarget) throws(CommandRefusal) {
        guard case .display(let display) = target else {
            return isPaused ? pauseAll() : resumeAll()
        }
        _ = try target.displays(connected: displays.map(\.identity))
        commit(state: state.settingPaused(isPaused, for: display))
    }

    /// Next on each display named that shows a playlist, paused or not.
    private func moveOn(_ target: DisplayTarget) throws(CommandRefusal) -> CommandReply {
        let moving = try state.displaysMovingOn(target, connected: displays.map(\.identity))
        for display in moving {
            next(on: display)
        }
        return .movedOn(moving.map { identity in
            (display: display(identity)?.name ?? identity.description, wallpaper: state.wallpaper(shownOn: identity, in: library)?.name)
        })
    }
}
