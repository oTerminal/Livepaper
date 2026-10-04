import Foundation
import LivepaperCore

/// Why WallpaperAgent is to be restarted.
nonisolated public enum AgentRestartReason: Hashable, Sendable {
    /// The extension stayed silent until `judgeHeartbeat` reached `.restartAgent`.
    case silence
    /// The extension's spiral detector saw the agent reconnect in a loop.
    case spiral
    /// The extension's watchdog climbed its ladder to the top.
    case watchdog
    /// Someone called `recover(.restartAgent)`: the status line's button, or the developer menu.
    case user
}

/// Why a restart that was asked for is not made now.
nonisolated public enum AgentRestartRefusal: Equatable, Sendable {
    /// The last restart was less than `agentRestartGap` ago.
    case tooSoon(allowedFrom: Date)
    /// The last restart has not been followed by a heartbeat. An extension that
    /// never answers, though the store names Livepaper or cannot be read, would
    /// otherwise have the desktop redrawn every ten minutes, forever.
    case awaitingHeartbeat
}

/// What the host's status is reduced over.
nonisolated public enum HostEvent: Equatable, Sendable {
    /// `lastAgentRestart` is the last restart that an earlier launch recorded,
    /// so that relaunching the app does not open the gap early.
    case activated(at: Date, lastAgentRestart: Date? = nil)
    case heartbeat(Heartbeat, at: Date)
    /// The clock, at the reducer's `nextCheck`.
    case tick(at: Date)
    case systemWillSleep
    case systemDidWake(at: Date)
    /// `recover(.restartAgent)` was called.
    case restartRequested(at: Date)
    /// What `.readBeforeRestart` asked for, read at once: what the wallpaper
    /// store says of Livepaper, and the last restart any part of the app
    /// recorded in the shared `AgentRestartStore`, Selection's included.
    case readForRestart(AgentRestartReason, store: StoreSelection, lastAgentRestart: Date?, at: Date)
    case deactivated

    /// When the event happened; the two that carry no time change nothing that depends on it.
    public var time: Date? {
        switch self {
        case .activated(let at, _), .heartbeat(_, let at), .tick(let at), .systemDidWake(let at), .restartRequested(let at): at
        case .readForRestart(_, _, _, let at): at
        case .systemWillSleep, .deactivated: nil
        }
    }
}

/// What the reducer asks its owner to do.
nonisolated public enum HostAction: Equatable, Sendable {
    /// Post `HostNotification.recover` with this level: the extension tries it inside its process.
    case postRecover(RecoveryLevel)
    /// A level the extension would try inside its process, not posted: no
    /// heartbeat has come since activation, so no extension is there to receive it.
    case recoverSkipped(RecoveryLevel)
    case restartAgent(AgentRestartReason)
    /// Said once per reason until something changes, so that the log shows it without repeating it.
    case restartRefused(AgentRestartReason, AgentRestartRefusal)
    /// Before an automatic restart: read the wallpaper store (never write it)
    /// and the shared record of the last restart, and send `.readForRestart`
    /// in the same turn.
    case readBeforeRestart(AgentRestartReason)

    public var isReadBeforeRestart: Bool {
        if case .readBeforeRestart = self { true } else { false }
    }
}

/// The render host's status, reduced over heartbeats, silence and the clock.
///
/// A heartbeat gives `.live`, `.notSelected` or `.unavailable` by its flags.
/// Silence gives `.recovering(level)` by `judgeHeartbeat`, and each level is
/// acted on once as it is reached. Every restart of the agent, whatever asked
/// for it, goes through `allowAgentRestart`. On top of that, an automatic
/// restart is not made while the last restart has had no heartbeat since.
///
/// Not selected is not silence. WallpaperAgent launches the extension only
/// while Livepaper is the system wallpaper, so a user who chose another hears
/// nothing from it. Before an automatic restart the owner reads the wallpaper
/// store and the shared record of the last restart (`.readBeforeRestart`):
/// when the store names Livepaper nowhere, the status is `.notSelected`, no
/// restart is made and the ladder stops until a heartbeat, a wake or an
/// activation (no agent restart on an ordinary launch); when it
/// cannot be read, the ladder goes on. The record holds restarts made
/// elsewhere, Selection's among them, so the gap runs from those too.
///
/// Silence before the first heartbeat since activation is the install hazard:
/// the extension was killed and the agent has not started it
/// again. The levels below `.restartAgent` are notifications that the
/// extension handles in its own process, so with no extension nobody receives
/// them. Until a heartbeat has come, they are skipped and said so, and the
/// agent is restarted one step after the grace period, where the ladder
/// would have reached `.rebuildSurface`. Once one has come, silence climbs
/// the whole ladder.
///
/// A wake starts a new grace period, because the extension's heartbeat from
/// before the sleep is old by then and says nothing about whether it is alive.
/// It does not count as a heartbeat. An event long after the check that was
/// due is a wake too: the timer could not make the check, so the Mac slept
/// through it, and the sleep and the wake may be heard after it, or never.
nonisolated public struct HostStatusReducer: Equatable, Sendable {
    /// How far past a change of `judgeHeartbeat`'s answer the next check lands,
    /// so that it lands on the far side of it.
    static let resolution: Duration = .milliseconds(1)

    private enum Phase: Equatable, Sendable {
        case stopped
        case awake(graceFrom: Date)
        case asleep
    }

    public let timing: HeartbeatTiming
    public private(set) var status: RenderHostStatus = .stopped
    public private(set) var lastHeartbeat: Heartbeat?
    public private(set) var lastHeartbeatAt: Date?
    public private(set) var lastAgentRestart: Date?
    /// The agent was restarted and no heartbeat has come since.
    public private(set) var restartUnanswered = false
    /// When the owner should send the next `.tick`: the moment `judgeHeartbeat`'s
    /// answer next changes, or the restart gap opens. `nil` when nothing can
    /// change until an event arrives, so the owner's timer stops.
    public private(set) var nextCheck: Date?

    private var phase = Phase.stopped
    private var activatedAt: Date?
    /// The highest level acted on in this silence.
    private var climbed: RecoveryLevel?
    private var refusalsSaid: Set<AgentRestartReason> = []
    /// The automatic restart waiting for `.readForRestart`.
    private var reading: AgentRestartReason?
    /// The store named Livepaper nowhere when silence last reached the agent.
    /// Kept through a wake, since a wake changes no store; a heartbeat or an
    /// activation ends it, and so does the store naming Livepaper again.
    private var storeNamesLivepaperNowhere = false

    public init(timing: HeartbeatTiming = .standard) {
        self.timing = timing
    }

    public mutating func reduce(_ event: HostEvent) -> [HostAction] {
        if let now = event.time, sleptThroughCheck(before: now) { wake(at: now) }
        var actions: [HostAction] = []
        switch event {
        case .activated(let at, let recorded): activate(at: at, lastAgentRestart: recorded)
        case .heartbeat(let heartbeat, let at): actions = receive(heartbeat, at: at)
        case .tick(let at): actions = climb(at: at)
        case .systemWillSleep: if case .awake = phase { phase = .asleep }
        case .systemDidWake(let at): wake(at: at)
        case .restartRequested(let at): actions = requestRestart(.user, at: at)
        case .readForRestart(let reason, let store, let recorded, let at):
            actions = read(reason, store: store, lastAgentRestart: recorded, at: at)
        case .deactivated: deactivate()
        }
        status = derivedStatus(at: event.time)
        nextCheck = event.time.flatMap(nextCheck(after:))
        return actions
    }

    /// An activation starts afresh, keeping the restart an earlier launch recorded.
    private mutating func activate(at now: Date, lastAgentRestart recorded: Date?) {
        phase = .awake(graceFrom: now)
        activatedAt = now
        climbed = nil
        reading = nil
        storeNamesLivepaperNowhere = false
        keep(recorded, at: now)
    }

    /// A restart recorded by another launch or another part of the app: the
    /// later of it and the one known. One recorded later than now was recorded
    /// before the clock moved back, and counts as made now, so that the gap
    /// still runs, and no longer.
    private mutating func keep(_ recorded: Date?, at now: Date) {
        guard let recorded else { return }
        lastAgentRestart = max(lastAgentRestart ?? .distantPast, min(recorded, now))
    }

    private mutating func wake(at now: Date) {
        guard phase != .stopped else { return }
        phase = .awake(graceFrom: now)
        climbed = nil
    }

    /// The timer makes a check within a fraction of a second of `nextCheck`.
    /// Half a step later it could not have: the Mac was asleep. A check late by
    /// less, and so judged, reaches no level past the one it was due for.
    private func sleptThroughCheck(before now: Date) -> Bool {
        guard let due = nextCheck else { return false }
        return now > due + timing.step / 2
    }

    private mutating func deactivate() {
        phase = .stopped
        climbed = nil
        reading = nil
    }

    private mutating func receive(_ heartbeat: Heartbeat, at now: Date) -> [HostAction] {
        guard phase != .stopped else { return [] }
        // A heartbeat proves the Mac is awake, even if the wake itself was not heard.
        if phase == .asleep { phase = .awake(graceFrom: now) }
        lastHeartbeat = heartbeat
        lastHeartbeatAt = now
        restartUnanswered = false
        storeNamesLivepaperNowhere = false
        reading = nil
        climbed = nil
        refusalsSaid.remove(.silence)
        if !heartbeat.flags.contains(.spiralDetected) { refusalsSaid.remove(.spiral) }
        if !heartbeat.flags.contains(.restartAgentRequested) { refusalsSaid.remove(.watchdog) }

        if heartbeat.flags.contains(.spiralDetected) { return requestRestart(.spiral, at: now) }
        if heartbeat.flags.contains(.restartAgentRequested) { return requestRestart(.watchdog, at: now) }
        return []
    }

    private mutating func climb(at now: Date) -> [HostAction] {
        guard let level = levelReached(at: now) else { return [] }
        var actions: [HostAction] = []
        if climbed.map({ level > $0 }) ?? true {
            if heardSinceActivation {
                if level < .restartAgent { actions.append(.postRecover(level)) }
            } else {
                let skipped = RecoveryLevel.allCases.filter { passed in
                    passed < .restartAgent && passed <= level && climbed.map { passed > $0 } ?? true
                }
                actions += skipped.map(HostAction.recoverSkipped)
            }
            climbed = level
        }
        if level == .restartAgent { actions += requestRestart(.silence, at: now) }
        return actions
    }

    /// A click restarts at once, within the gap the host knows of: its answer is
    /// told by `lastAgentRestart` moving. An automatic restart that the host's
    /// own record allows is read for first.
    private mutating func requestRestart(_ reason: AgentRestartReason, at now: Date) -> [HostAction] {
        if reason != .user, restartUnanswered {
            return refuse(reason, .awaitingHeartbeat)
        }
        if let refusal = gapRefusal(reason, at: now) { return refusal }
        guard reason == .user else {
            reading = reason
            return [.readBeforeRestart(reason)]
        }
        return restart(reason, at: now)
    }

    /// What was read for an automatic restart: the gap counts from the latest
    /// restart anyone recorded, and silence with Livepaper named nowhere in the
    /// store is not selected, and restarts nothing.
    private mutating func read(
        _ reason: AgentRestartReason, store: StoreSelection, lastAgentRestart recorded: Date?, at now: Date
    ) -> [HostAction] {
        guard reading == reason, phase != .stopped else { return [] }
        reading = nil
        keep(recorded, at: now)
        if reason == .silence {
            storeNamesLivepaperNowhere = store == .notSelected
            if storeNamesLivepaperNowhere { return [] }
        }
        if let refusal = gapRefusal(reason, at: now) { return refusal }
        return restart(reason, at: now)
    }

    /// Nil when the gap allows a restart now; else the refusal, said once per reason.
    private mutating func gapRefusal(_ reason: AgentRestartReason, at now: Date) -> [HostAction]? {
        guard let last = lastAgentRestart, !allowAgentRestart(last: last, now: now) else { return nil }
        return refuse(reason, .tooSoon(allowedFrom: last + agentRestartGap))
    }

    private mutating func restart(_ reason: AgentRestartReason, at now: Date) -> [HostAction] {
        lastAgentRestart = now
        restartUnanswered = true
        refusalsSaid.removeAll()
        return [.restartAgent(reason)]
    }

    private mutating func refuse(_ reason: AgentRestartReason, _ refusal: AgentRestartRefusal) -> [HostAction] {
        // A click always gets its answer; the automatic reasons ask again on every heartbeat or tick.
        guard reason == .user || refusalsSaid.insert(reason).inserted else { return [] }
        return [.restartRefused(reason, refusal)]
    }

    private func judge(at now: Date) -> RecoveryLevel? {
        guard case .awake(let graceFrom) = phase else { return nil }
        return judgeHeartbeat(last: lastHeartbeatAt, now: now, launchedAt: graceFrom, timing: timing)
    }

    /// `judgeHeartbeat`'s level, except that before the first heartbeat since
    /// activation every level past the first is `.restartAgent`.
    private func levelReached(at now: Date) -> RecoveryLevel? {
        guard let level = judge(at: now) else { return nil }
        return heardSinceActivation || level == .flush ? level : .restartAgent
    }

    private var heardSinceActivation: Bool {
        guard let heard = lastHeartbeatAt, let activatedAt else { return false }
        return heard >= activatedAt
    }

    private func derivedStatus(at now: Date?) -> RenderHostStatus {
        switch phase {
        case .stopped:
            return .stopped
        case .asleep:
            return status
        case .awake:
            if storeNamesLivepaperNowhere { return .notSelected }
            if restartUnanswered { return .recovering(.restartAgent) }
            if let now, let level = levelReached(at: now) { return .recovering(level) }
            guard heardSinceActivation, let heartbeat = lastHeartbeat else { return .connecting }
            return Self.status(for: heartbeat.flags)
        }
    }

    private static func status(for flags: Heartbeat.Flags) -> RenderHostStatus {
        if flags.contains(.selfCheckFailed) { return .unavailable }
        return flags.contains(.desktopSurfaceAcquired) ? .live : .notSelected
    }

    /// Where `levelReached` next changes its answer. `judgeHeartbeat` counts its steps from
    /// the moment the last heartbeat expires, or from the end of the grace
    /// period when there has been none since it began, and says nothing before
    /// the grace period ends.
    private func nextCheck(after now: Date) -> Date? {
        guard case .awake(let graceFrom) = phase else { return nil }
        if levelReached(at: now) == .restartAgent {
            guard !restartUnanswered, !storeNamesLivepaperNowhere, let last = lastAgentRestart else { return nil }
            let gapOpens = last + agentRestartGap
            return gapOpens > now ? gapOpens + Self.resolution : nil
        }
        let graceEnds = graceFrom + timing.grace
        let anchor: Date
        if let heard = lastHeartbeatAt, heard >= graceFrom {
            anchor = heard + timing.lifetime
        } else {
            anchor = graceEnds
        }
        let first = max(anchor, graceEnds)
        if now < first { return first + Self.resolution }
        let step = timing.step.timeInterval
        let stepsTaken = (now.timeIntervalSince(anchor) / step).rounded(.down)
        return anchor.addingTimeInterval((stepsTaken + 1) * step) + Self.resolution
    }
}
