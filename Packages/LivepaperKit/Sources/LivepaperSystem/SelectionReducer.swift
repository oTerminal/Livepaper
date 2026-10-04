import Foundation
import LivepaperCore

/// Why System Settings was opened at Wallpaper for the user to finish there.
nonisolated public enum SelectionFallback: Equatable, Sendable {
    /// pluginkit does not list the extension, so WallpaperAgent cannot launch it.
    case notListed
    /// The store could not be read or written, is of a shape this build does not know, or,
    /// leaving, has no usable kept copy.
    case store(WallpaperStoreError)
    /// No `.live` within `SelectionReducer.wait` of asking.
    case noLiveInTime
}

/// Where selecting or leaving has got to, for the onboarding card and the Settings row.
nonisolated public enum SelectionOutcome: Equatable, Sendable {
    case idle
    case working
    /// Livepaper is the system wallpaper: the heartbeat says a desktop surface is acquired.
    case selected
    /// System Settings is open at Wallpaper for the user to choose "Livepaper". The wait for
    /// `.live` goes on, and the click brings it.
    case chooseInPane(SelectionFallback)
    /// The previous wallpaper is back.
    case left
    /// System Settings is open at Wallpaper for the user to choose another wallpaper: the
    /// previous one could not be put back.
    case chooseAnotherInPane(SelectionFallback)
    /// System Settings could not be opened either, so the words send the user there. Selecting
    /// still waits for `.live`.
    case failed(SelectionFallback, leaving: Bool)

    /// What the card or the row says, for the outcomes that need words of their own.
    public var words: String? {
        switch self {
        case .idle, .working, .selected, .left: nil
        case .chooseInPane: "System Settings is open at Wallpaper: choose “Livepaper” there."
        case .chooseAnotherInPane: "System Settings is open at Wallpaper: choose the wallpaper you want there."
        case .failed(_, leaving: false): "Open System Settings, go to Wallpaper and choose “Livepaper”."
        case .failed(_, leaving: true): "Open System Settings, go to Wallpaper and choose the wallpaper you want."
        }
    }
}

nonisolated public enum SelectionEvent: Equatable, Sendable {
    /// Selecting was asked for; `host` is the render host's status at that moment.
    case select(at: Date, host: RenderHostStatus)
    case leave
    /// pluginkit answered whether it lists the extension.
    case listed(Bool)
    /// The store edit answered: the select's or the leave's, whichever was asked for.
    case edited(Result<WallpaperStoreEdit, WallpaperStoreError>)
    case agentRestarted(AgentRestartOutcome)
    case paneOpened(Bool)
    case host(RenderHostStatus, at: Date)
    /// The clock, at `deadline`.
    case tick(at: Date)
}

nonisolated public enum SelectionEffect: Equatable, Sendable {
    /// Ask pluginkit whether it lists the extension.
    case checkListed
    /// Make every Desktop entry name Livepaper, keeping the store as it was first.
    case writeSelection
    /// Put back from the kept copy wherever Livepaper is still named.
    case writeDeselection
    /// Restart WallpaperAgent: one signal, then wait for it to come back.
    case restartAgent
    /// Open System Settings at Wallpaper, for the user's click.
    case openPane(SelectionFallback)
    /// Leaving is done: the kept copy goes.
    case removeKeptCopy
    /// For the log: `.live` came this long after selecting was asked for.
    case reportLive(after: Duration)
    /// For the log: the host was live when selecting was asked for, so nothing was done.
    case reportAlreadyLive
}

/// Selecting Livepaper as the system wallpaper, and leaving it: a pure reducer over the
/// answers of pluginkit, the store, the agent and the host, and the clock.
///
/// Selecting: nothing when the host is `.live` already. Otherwise pluginkit must list the
/// extension, then the store is edited, then WallpaperAgent is restarted once; only the
/// heartbeat's `.live` says it worked. A store already naming Livepaper everywhere is not
/// written and the agent not restarted: the flag completes it. With no `.live` within `wait` of
/// asking, or at once when pluginkit does not list the extension or the store cannot be read or
/// written, System Settings opens at Wallpaper and the wait for `.live` goes on without a
/// deadline, since the user's click there brings it. Answers that arrive after that are
/// dropped: nothing is written behind the user's back while they are in the pane.
///
/// Leaving: the store is put back, WallpaperAgent restarted once, then the kept copy goes.
/// Nothing is written and nothing restarted when Livepaper is named nowhere. With no usable
/// copy, System Settings opens for the user to choose another wallpaper.
nonisolated public struct SelectionReducer: Equatable, Sendable {
    /// How long selecting waits for `.live` before opening the pane: past the host's grace
    /// period (`HeartbeatTiming.standard.grace`, 20 s), in which the extension is given its
    /// first heartbeat, and far past the 0.27 s the spike took from the write to the agent's acquire.
    public static let wait: Duration = .seconds(30)

    private enum Step: Equatable, Sendable {
        case idle
        case checking
        case writing
        case restarting
        /// The store names Livepaper; waiting for `.live` until the deadline.
        case waiting
        /// The pane is open, or could not be; waiting for `.live` with no deadline.
        case waitingForClick
        case selected
        case leavingWrite
        case leavingRestart
        case left
        case leaveInPane
    }

    public private(set) var outcome: SelectionOutcome = .idle
    /// When the owner should send `.tick`: the end of the wait for `.live`. Nil when nothing waits on the clock.
    public private(set) var deadline: Date?
    private var step = Step.idle
    private var askedAt: Date?

    public init() {}

    /// Whether a select or a leave is under way, so that another is not started.
    public var isBusy: Bool {
        [.checking, .writing, .restarting, .waiting, .leavingWrite, .leavingRestart].contains(step)
    }

    /// Whether the host's status still matters: a select is under way or waits for the user's click.
    public var awaitsLive: Bool {
        [.checking, .writing, .restarting, .waiting, .waitingForClick].contains(step)
    }

    public mutating func reduce(_ event: SelectionEvent) -> [SelectionEffect] {
        switch event {
        case .select(let at, let host): select(at: at, host: host)
        case .leave: leave()
        case .listed(let listed): self.listed(listed)
        case .edited(let result): edited(result)
        case .agentRestarted: restarted()
        case .paneOpened(let opened): paneOpened(opened)
        case .host(let status, let at): status == .live ? live(at: at) : []
        case .tick(let at): tick(at: at)
        }
    }

    private mutating func listed(_ listed: Bool) -> [SelectionEffect] {
        guard listed else { return fallBack(from: [.checking], .notListed) }
        return proceed(from: .checking, to: .writing, [.writeSelection])
    }

    private mutating func tick(at now: Date) -> [SelectionEffect] {
        guard let deadline, now >= deadline else { return [] }
        return fallBack(from: [.checking, .writing, .restarting, .waiting], .noLiveInTime)
    }

    private mutating func select(at now: Date, host: RenderHostStatus) -> [SelectionEffect] {
        guard !isBusy else { return [] }
        askedAt = now
        if host == .live {
            finish(.selected, at: .selected)
            return [.reportAlreadyLive]
        }
        step = .checking
        outcome = .working
        deadline = now + Self.wait
        return [.checkListed]
    }

    private mutating func leave() -> [SelectionEffect] {
        guard !isBusy else { return [] }
        step = .leavingWrite
        outcome = .working
        deadline = nil
        return [.writeDeselection]
    }

    private mutating func proceed(from expected: Step, to next: Step, _ effects: [SelectionEffect]) -> [SelectionEffect] {
        guard step == expected else { return [] }
        step = next
        return effects
    }

    private mutating func edited(_ result: Result<WallpaperStoreEdit, WallpaperStoreError>) -> [SelectionEffect] {
        switch (step, result) {
        case (.writing, .success(let edit)):
            // A store already naming Livepaper everywhere needs no restart: the flag completes it.
            return edit.wrote ? proceed(from: .writing, to: .restarting, [.restartAgent]) : proceed(from: .writing, to: .waiting, [])
        case (.writing, .failure(let error)):
            return fallBack(from: [.writing], .store(error))
        case (.leavingWrite, .success(let edit)):
            if edit.wrote { return proceed(from: .leavingWrite, to: .leavingRestart, [.restartAgent]) }
            finish(.left, at: .left)
            return [.removeKeptCopy]
        case (.leavingWrite, .failure(let error)):
            step = .leaveInPane
            outcome = .chooseAnotherInPane(.store(error))
            return [.openPane(.store(error))]
        default:
            return []
        }
    }

    private mutating func restarted() -> [SelectionEffect] {
        switch step {
        case .restarting:
            step = .waiting
            return []
        case .leavingRestart:
            finish(.left, at: .left)
            return [.removeKeptCopy]
        default:
            return []
        }
    }

    private mutating func live(at now: Date) -> [SelectionEffect] {
        guard awaitsLive else { return [] }
        // To the millisecond: it is for the log, and the clock is no finer than that anyway.
        let after = askedAt.map { Duration.milliseconds(Int((now.timeIntervalSince($0) * 1000).rounded())) } ?? .zero
        finish(.selected, at: .selected)
        return [.reportLive(after: after)]
    }

    private mutating func fallBack(from expected: [Step], _ why: SelectionFallback) -> [SelectionEffect] {
        guard expected.contains(step) else { return [] }
        step = .waitingForClick
        outcome = .chooseInPane(why)
        deadline = nil
        return [.openPane(why)]
    }

    private mutating func paneOpened(_ opened: Bool) -> [SelectionEffect] {
        guard !opened else { return [] }
        switch outcome {
        case .chooseInPane(let why): outcome = .failed(why, leaving: false)
        case .chooseAnotherInPane(let why): outcome = .failed(why, leaving: true)
        default: break
        }
        return []
    }

    private mutating func finish(_ outcome: SelectionOutcome, at step: Step) {
        self.step = step
        self.outcome = outcome
        deadline = nil
    }
}
