import Foundation

/// The recovery ladder, mildest first. The watchdog walks it after a stall and
/// the app walks it after launch when no heartbeat arrives.
public enum RecoveryLevel: Int, CaseIterable, Comparable, Sendable {
    case flush
    case rebuildSurface
    case rebuildPipeline
    case restartAgent

    public static func < (lhs: RecoveryLevel, rhs: RecoveryLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The level for the given number of levels already climbed, ending at `.restartAgent`.
    init(step: Int) {
        let last = Self.allCases.count - 1
        self = Self.allCases[min(max(step, 0), last)]
    }
}

public enum WatchdogVerdict: Equatable, Sendable {
    case healthy
    case recover(RecoveryLevel)

    public static let flush = WatchdogVerdict.recover(.flush)
    public static let rebuildSurface = WatchdogVerdict.recover(.rebuildSurface)
    public static let rebuildPipeline = WatchdogVerdict.recover(.rebuildPipeline)
    public static let restartAgent = WatchdogVerdict.recover(.restartAgent)
}

/// Judges whether a surface is showing new pictures.
///
/// `before` and `after` are displayed-picture counts taken at the two ends of a
/// window in which `expected` pictures should have been shown. A running
/// timebase proves nothing, so pictures are what is counted.
/// Half the expected pictures or more is healthy. Otherwise the verdict is the
/// next recovery, where `attempt` is how many have already been tried for this stall.
///
/// Only ask about a surface that is on screen: the window server throttles a
/// hidden one, and it would look stalled.
public func judgeProgress(before: Int, after: Int, expected: Int, attempt: Int) -> WatchdogVerdict {
    let displayed = max(after - before, 0)
    if displayed * 2 >= expected { return .healthy }
    return .recover(RecoveryLevel(step: attempt))
}

/// The least time between two restarts of WallpaperAgent, whoever asks for them.
public let agentRestartGap: Duration = .seconds(600)

/// Whether WallpaperAgent may be restarted now. Both the watchdog's and the
/// heartbeat's `.restartAgent` go through here, so the agent is never restarted
/// twice within `minimumGap`.
public func allowAgentRestart(last: Date?, now: Date, minimumGap: Duration = agentRestartGap) -> Bool {
    guard let last else { return true }
    return now.elapsed(since: last) >= minimumGap
}

/// How often the extension sends its heartbeat, and how long the app waits for it before acting.
public struct HeartbeatTiming: Equatable, Sendable {
    /// The extension sends one heartbeat every `interval`. It is shorter than
    /// `lifetime`, so that one late heartbeat is not taken for silence.
    public var interval: Duration
    /// After launch, how long the extension has to send its first heartbeat.
    public var grace: Duration
    /// How long a heartbeat counts for.
    public var lifetime: Duration
    /// How long each recovery level is given before the next is tried.
    public var step: Duration

    public init(interval: Duration, grace: Duration, lifetime: Duration, step: Duration) {
        self.interval = interval
        self.grace = grace
        self.lifetime = lifetime
        self.step = step
    }

    /// Measured on the product extension on 2026-09-22, macOS 27.0. Heartbeats
    /// came every 5.00 s, gaps 4.80 to 5.11 s over 4 minutes, and 13 ms after
    /// the app applied a state, since the extension beats on each change of
    /// render state. After an agent restart the extension's first heartbeat
    /// came in 0.07 s. The install hazard recovered with the desktop live
    /// 30.6 s after launch: the restart at grace plus one step, then 0.57 s for
    /// the agent and the extension to come back. The grace stays at 20 s to
    /// leave the extension room to come up at login.
    public static let standard = HeartbeatTiming(interval: .seconds(5), grace: .seconds(20), lifetime: .seconds(15), step: .seconds(10))
}

/// Judges the extension's heartbeat: `nil` while all is well, otherwise the
/// recovery level that the silence has reached.
///
/// After an install or update the first extension instance is killed once by
/// the next app launch, and the agent does not start it again.
/// The spike found no time window for that, so the rule is only "no heartbeat
/// after the grace period". The level depends on time alone: the caller acts
/// when it changes, and sends `.restartAgent` through `allowAgentRestart`.
public func judgeHeartbeat(last: Date?, now: Date, launchedAt: Date, timing: HeartbeatTiming = .standard) -> RecoveryLevel? {
    let sinceLaunch = now.elapsed(since: launchedAt)
    guard sinceLaunch >= timing.grace else { return nil }

    let overdue: Duration
    if let last, last >= launchedAt {
        overdue = now.elapsed(since: last) - timing.lifetime
        guard overdue > .zero else { return nil }
    } else {
        overdue = sinceLaunch - timing.grace
    }
    return RecoveryLevel(step: Int(overdue / timing.step))
}
