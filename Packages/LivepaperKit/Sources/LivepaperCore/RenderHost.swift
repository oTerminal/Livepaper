import Foundation

/// What a render host can do, so that policy does not need to know which host it is.
public struct HostCapabilities: Equatable, Sendable {
    /// The host draws on the lock screen, so a locked display keeps playing.
    public var showsLockScreen: Bool

    public init(showsLockScreen: Bool) {
        self.showsLockScreen = showsLockScreen
    }
}

/// What a render host reports about itself, for the status line and for onboarding.
public enum RenderHostStatus: Equatable, Sendable {
    /// Not activated, or deactivated: the host holds a still.
    case stopped
    /// Activated, and no heartbeat has arrived yet.
    case connecting
    /// The host is alive but has no desktop surface: Livepaper is not the system wallpaper.
    case notSelected
    case live
    /// The host went quiet or stalled, and this recovery is being tried.
    case recovering(RecoveryLevel)
    /// The host cannot run on this macOS: its launch self-check failed.
    case unavailable
}

extension RenderHostStatus {
    /// Its name in the host's log lines, the socket's `status` and the
    /// diagnostics report, which other tools read: `live`, `recovering(flush)`.
    public var name: String {
        switch self {
        case .stopped: "stopped"
        case .connecting: "connecting"
        case .notSelected: "notSelected"
        case .live: "live"
        case .recovering(let level): "recovering(\(String(describing: level)))"
        case .unavailable: "unavailable"
        }
    }

    /// What the popover's status line and `livepaper status` say of it. The
    /// line says more where it knows more: how many displays are live, Paused,
    /// and the wallpaper service not responding.
    public var words: String {
        switch self {
        case .stopped: "Stopped"
        case .connecting: "Connecting to the wallpaper service"
        case .notSelected: "Livepaper is not your wallpaper"
        case .live: "Live"
        case .recovering: "Recovering the wallpaper"
        case .unavailable: "Not available on this version of macOS"
        }
    }
}

/// The part of the system that puts a playing wallpaper on screen.
///
/// The wallpaper extension's client is the one real host. The
/// seam is kept so that screens can be built on a fake, and so that a window
/// host stays addable.
@MainActor
public protocol RenderHost: AnyObject {
    var capabilities: HostCapabilities { get }
    func activate() async throws
    /// The full state every time: applying the same state twice changes nothing.
    func apply(_ state: RenderState) async
    var status: AsyncStream<RenderHostStatus> { get }
    /// `.restartAgent` restarts WallpaperAgent through `allowAgentRestart`, and
    /// returns once it is back or the restart was refused.
    func recover(_ level: RecoveryLevel) async
    /// When WallpaperAgent was last restarted, by any launch; nil when never.
    /// Read after `recover(.restartAgent)`, it tells a restart from a refusal.
    var lastAgentRestart: Date? { get }
    /// Writes the stopped render state: the host holds a still and releases its decoders.
    func deactivate() async
}
