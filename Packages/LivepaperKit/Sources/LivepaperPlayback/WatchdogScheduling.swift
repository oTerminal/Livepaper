import LivepaperCore

/// Why the watchdog checks that pictures advance.
public enum WatchdogTrigger: String, Equatable, Sendable {
    /// `WatchdogSchedule.delayAfterWake` after the Mac wakes.
    case wake
    case unlock
    /// A recovery was tried, by the watchdog's ladder or at the app's request.
    case recovery
    /// The agent's `update` for a surface.
    case update
    /// The app's `HostNotification.check`.
    case check
}

/// What the watchdog knows of one surface when it picks the ones to judge.
public struct WatchdogCandidate: Equatable, Sendable {
    /// Acquired and not invalidated.
    public var isLive: Bool
    public var isPreview: Bool
    public var mode: SurfaceMode
    public var state: SurfacePlaybackState
    /// The render state's `coveredDisplays` holds the surface's display.
    public var displayCovered: Bool
    /// The render state's `asleepDisplays` holds it.
    public var displayAsleep: Bool

    public init(
        isLive: Bool, isPreview: Bool, mode: SurfaceMode, state: SurfacePlaybackState, displayCovered: Bool, displayAsleep: Bool
    ) {
        self.isLive = isLive
        self.isPreview = isPreview
        self.mode = mode
        self.state = state
        self.displayCovered = displayCovered
        self.displayAsleep = displayAsleep
    }
}

/// What the watchdog does about one surface after counting its pictures.
public enum WatchdogStep: Equatable, Sendable {
    case healthy
    /// Too few pictures shown while the engine fed the renderer as usual: the
    /// window server is not compositing the surface, as under a fullscreen app
    /// the render state does not know of. Not a stall, so nothing is tried
    /// and the ladder stays where it was.
    case notComposited
    /// `.flush`, `.rebuildSurface` or `.rebuildPipeline`, tried inside the process.
    case recover(RecoveryLevel)
    /// The ladder's top: the app is asked to restart WallpaperAgent through the
    /// heartbeat's `restartAgentRequested`, since the sandbox keeps the
    /// extension from doing it.
    case requestRestart
}

/// When the watchdog checks, which surfaces it judges, and how far up the
/// recovery ladder each has climbed.
///
/// A check runs at a time. A trigger that arrives during one runs one more
/// check after it, for the latest reason, so a recovery tried in a check is
/// always followed by another. The restart request stands while any surface
/// that climbed to the top has neither been judged healthy since nor gone
/// away; a new extension process starts without it.
public struct WatchdogSchedule: Equatable, Sendable {
    /// How long a check counts displayed pictures for.
    public static let window: Duration = .seconds(2)
    /// How long after a wake the playback decision is taken again and the check runs.
    public static let delayAfterWake: Duration = .seconds(1)

    public private(set) var isChecking = false
    public private(set) var pending: WatchdogTrigger?
    /// Recoveries tried on each surface since it was last healthy.
    public private(set) var attempts: [SurfaceID: Int] = [:]
    /// The surfaces whose ladder reached the agent restart.
    public private(set) var restartRequests: Set<SurfaceID> = []

    public init() {}

    /// The heartbeat's `restartAgentRequested`.
    public var restartAgentRequested: Bool { !restartRequests.isEmpty }

    /// The surfaces last judged stalled.
    public var stalled: [SurfaceID] {
        Set(attempts.keys).union(restartRequests).sorted { $0.description < $1.description }
    }

    /// Whether a check starts now. During a check the trigger waits for it to end.
    public mutating func request(_ trigger: WatchdogTrigger) -> Bool {
        guard !isChecking else {
            pending = trigger
            return false
        }
        isChecking = true
        return true
    }

    /// A check ended. Returns the trigger of the one to run next, if any came in meanwhile.
    public mutating func finish() -> WatchdogTrigger? {
        guard let next = pending else {
            isChecking = false
            return nil
        }
        pending = nil
        return next
    }

    /// Only a surface that plays and is on screen can be judged: the window
    /// server shows no new pictures on a covered display and throttles the
    /// Settings preview when Settings is behind, which would look like a
    /// stall. The lock screen is above every window, so covering does not
    /// count there.
    public static func mayJudge(_ candidate: WatchdogCandidate) -> Bool {
        candidate.isLive
            && !candidate.isPreview
            && candidate.state == .playing
            && !candidate.displayAsleep
            && (candidate.mode == .locked || !candidate.displayCovered)
    }

    /// Judges a surface's pictures over `window` and takes the next step of its
    /// ladder. Too few pictures is a stall only when the engine fed too few
    /// frames as well: fed at least half the expected ones, as `judgeProgress`
    /// asks of the pictures, the surface is not composited. So is a scene whose
    /// display link was not asked for frames while its engine stood ready
    /// (`PictureCount.withheld`): covered, the system stops asking, and an agent
    /// restart would not bring its frames back.
    public mutating func judge(_ surface: SurfaceID, _ count: PictureCount) -> WatchdogStep {
        let attempt = attempts[surface, default: 0]
        let verdict = judgeProgress(before: 0, after: count.displayed, expected: count.expected, attempt: attempt)
        if verdict != .healthy, count.fed * 2 >= count.expected || count.withheld { return .notComposited }
        switch verdict {
        case .healthy:
            attempts[surface] = nil
            restartRequests.remove(surface)
            return .healthy
        case .recover(.restartAgent):
            restartRequests.insert(surface)
            return .requestRestart
        case .recover(let level):
            attempts[surface] = attempt + 1
            return .recover(level)
        }
    }

    /// The app asks for `level` on the stalled surfaces (`HostNotification.recover`).
    /// Returns them; their ladders continue above `level`, never below where they were.
    public mutating func recoveryRequested(_ level: RecoveryLevel) -> [SurfaceID] {
        guard level < .restartAgent else { return [] }
        let surfaces = stalled
        for surface in surfaces {
            attempts[surface] = max(attempts[surface, default: 0], level.rawValue + 1)
        }
        return surfaces
    }

    /// A surface went: its ladder and any restart it asked for go with it.
    public mutating func forget(_ surface: SurfaceID) {
        attempts[surface] = nil
        restartRequests.remove(surface)
    }
}
