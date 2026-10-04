import Foundation

/// What the soak counts from one log line. The wording each case is read from
/// is the logs' own (`SupervisorLog`, `ExtensionLog`, `BridgeLog`,
/// `HostLog`, `RotationLog`, `PlaybackMetrics`).
public enum SoakEvent: Equatable, Sendable {
    // MARK: The supervisor, in the extension

    case acquired(SurfaceTag, reused: Bool)
    case invalidated(SurfaceTag)
    case tornDown(SurfaceTag)
    /// `now showing`, `holding still` or `showing nothing`.
    case shows(SurfaceTag, SurfaceContent)
    /// The agent's `update`: the surface moved to the lock screen or back to the desktop.
    case mode(SurfaceTag, isLocked: Bool)
    case decision(display: String, DisplayDecision)
    case checkStarted(reason: String, surfaces: Int)
    case counted(SurfaceTag, PictureTally)
    /// `attempt` is how many recoveries had been tried on the surface before it.
    case verdict(SurfaceTag, CheckVerdict, attempt: Int)
    case recoveryTried(SurfaceTag, LadderLevel)
    case restartRequested(SurfaceTag)

    // MARK: The extension and its bridge

    case extensionLaunched(pid: Int)
    case woke(WakeSource)
    case unlocked
    case displayReconfigured(display: String)
    /// The agent connected. A new PID is a new agent: a restart, the app's or `killall WallpaperAgent`.
    case agentConnected(pid: Int)
    case selfCheck(isUsable: Bool, missing: [String])
    case spiral(emptyConnections: Int)

    // MARK: The app

    case hostStatus(HostPhase)
    case agentRestarting(reason: String)
    case agentRestarted(previous: Int, current: Int)
    case rotated(RotationCause, displays: [String])

    // MARK: The engine

    case metrics(MetricsLine)
}

/// What every supervisor line about one surface carries, as logged.
public struct SurfaceTag: Hashable, Sendable {
    public var surface: String
    public var display: String
    public var isPreview: Bool
    /// The wallpaper it shows or is about to; nil when the line says `none`.
    public var wallpaper: String?
    /// The render state's generation; nil before one was read.
    public var generation: UInt64?

    public init(surface: String, display: String, isPreview: Bool, wallpaper: String?, generation: UInt64?) {
        self.surface = surface
        self.display = display
        self.isPreview = isPreview
        self.wallpaper = wallpaper
        self.generation = generation
    }
}

public enum SurfaceContent: Equatable, Sendable {
    case playing
    case still
    case nothing
}

/// A display's decision, its pause and suspend reasons as the log names them.
public enum DisplayDecision: Equatable, Sendable {
    case play
    case pause(String)
    case suspend(String)
    case still
    case nothing

    /// Covered: `.pause(.desktopCovered)`, which the watchdog never judges.
    public var isCovered: Bool { self == .pause("desktopCovered") }
}

/// A `check count`: pictures displayed against those expected, and what the engine fed.
public struct PictureTally: Equatable, Sendable {
    public var displayed: Int
    public var expected: Int
    public var fed: Int
    /// A scene's: what its display link asked for and the window server presented.
    public var asked: Int?
    public var presented: Int?
    public var withheld: Bool

    public init(displayed: Int, expected: Int, fed: Int, asked: Int? = nil, presented: Int? = nil, withheld: Bool = false) {
        self.displayed = displayed
        self.expected = expected
        self.fed = fed
        self.asked = asked
        self.presented = presented
        self.withheld = withheld
    }
}

/// The recovery ladder's rungs, in the order it climbs them (`Watchdog.swift`).
public enum LadderLevel: String, CaseIterable, Comparable, Sendable {
    case flush
    case rebuildSurface
    case rebuildPipeline
    case restartAgent

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rung < rhs.rung
    }

    private var rung: Int {
        switch self {
        case .flush: 0
        case .rebuildSurface: 1
        case .rebuildPipeline: 2
        case .restartAgent: 3
        }
    }
}

/// A watchdog verdict. The ladder's top, `requestRestart`, is `.recover(.restartAgent)`.
public enum CheckVerdict: Equatable, Sendable {
    case healthy
    case notComposited
    case recover(LadderLevel)
}

/// The render host's status (`RenderHostStatus`).
public enum HostPhase: Equatable, Sendable {
    case stopped
    case connecting
    case notSelected
    case live
    case recovering(LadderLevel)
    case unavailable
}

public enum WakeSource: String, Sendable {
    case system
    case displays
}

public enum RotationCause: String, Sendable {
    case tick
    case wake
}
