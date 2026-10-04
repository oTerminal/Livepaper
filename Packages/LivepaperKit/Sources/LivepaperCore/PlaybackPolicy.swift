import Foundation

/// What is known about one display at the moment a playback decision is made.
///
/// `userPaused` is the user's intent and never expires. Everything else is
/// sensed, and counts only while it is fresh: the app senses for the extension,
/// and an app that has died must not leave the wallpaper frozen.
public struct PlaybackConditions: Equatable, Sendable {
    public var userPaused: Bool
    public var desktopCovered: Bool
    public var displayAsleep: Bool
    public var displayLocked: Bool
    public var lowPowerMode: Bool
    public var onBattery: Bool
    /// When the sensed conditions were observed.
    public var sensedAt: Date
    /// The time of the decision. Core never reads the clock.
    public var now: Date

    /// Sensed conditions older than this are ignored.
    public static let expiry: Duration = .seconds(30)

    public init(
        userPaused: Bool = false,
        desktopCovered: Bool = false,
        displayAsleep: Bool = false,
        displayLocked: Bool = false,
        lowPowerMode: Bool = false,
        onBattery: Bool = false,
        sensedAt: Date,
        now: Date
    ) {
        self.userPaused = userPaused
        self.desktopCovered = desktopCovered
        self.displayAsleep = displayAsleep
        self.displayLocked = displayLocked
        self.lowPowerMode = lowPowerMode
        self.onBattery = onBattery
        self.sensedAt = sensedAt
        self.now = now
    }

    var isStale: Bool {
        now.elapsed(since: sensedAt) > Self.expiry
    }
}

/// The pause rules the user can switch on and off, with the defaults the app ships.
public struct PauseRules: Codable, Equatable, Sendable {
    public var whenDesktopCovered: Bool
    public var whenDisplayAsleepOrLocked: Bool
    public var inLowPowerMode: Bool
    public var onBattery: Bool

    public init(
        whenDesktopCovered: Bool = true,
        whenDisplayAsleepOrLocked: Bool = true,
        inLowPowerMode: Bool = true,
        onBattery: Bool = false
    ) {
        self.whenDesktopCovered = whenDesktopCovered
        self.whenDisplayAsleepOrLocked = whenDisplayAsleepOrLocked
        self.inLowPowerMode = inLowPowerMode
        self.onBattery = onBattery
    }
}

public enum PauseReason: Equatable, Sendable {
    case user
    case desktopCovered
    case displayAsleep
    case displayLocked
    case lowPowerMode
    case onBattery
}

public enum PlaybackDecision: Equatable, Sendable {
    case play
    /// Stop advancing but keep the decoder: resuming is instant.
    case pause(PauseReason)
    /// Stop and release the decoder: the condition is expected to last.
    case suspend(PauseReason)
}

/// The one place that decides whether a display's wallpaper plays.
///
/// User pause beats everything. After that a reason to suspend beats a reason
/// to pause, because a released decoder is the larger saving.
public func decidePlayback(_ conditions: PlaybackConditions, rules: PauseRules, host: HostCapabilities) -> PlaybackDecision {
    if conditions.userPaused { return .pause(.user) }
    if conditions.isStale { return .play }

    // A locked display is showing the lock screen, not the desktop.
    let onLockScreen = conditions.displayLocked && host.showsLockScreen

    if rules.whenDisplayAsleepOrLocked {
        if conditions.displayAsleep { return .suspend(.displayAsleep) }
        if conditions.displayLocked, !host.showsLockScreen { return .suspend(.displayLocked) }
    }
    if rules.inLowPowerMode, conditions.lowPowerMode { return .suspend(.lowPowerMode) }
    if rules.onBattery, conditions.onBattery { return .suspend(.onBattery) }
    if rules.whenDesktopCovered, conditions.desktopCovered, !onLockScreen { return .pause(.desktopCovered) }
    return .play
}
