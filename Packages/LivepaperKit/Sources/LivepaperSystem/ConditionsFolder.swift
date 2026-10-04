import Foundation
import LivepaperCore

/// What the sensors report, and what else decides whether conditions need refreshing.
nonisolated public enum SensorEvent: Equatable, Sendable {
    case displays(Set<DisplayIdentity>)
    case covered(Set<DisplayIdentity>)
    case asleep(Set<DisplayIdentity>)
    case locked(Bool)
    case power(PowerState)
    /// The user's pause rules, which say whether any condition would pause a display.
    case rules(PauseRules)
    /// The clock, at `nextRefresh`.
    case tick
}

/// Folds sensor events into the `SensedConditions` that go into the render state.
///
/// Each change gives new conditions, stamped with the time it was sensed.
/// While the pause rules would pause or suspend some connected display on
/// what is sensed, the same conditions are given again every half of
/// `PlaybackConditions.expiry`, so that a live app never lets them go stale and
/// the extension keeps pausing. Otherwise nothing is refreshed: conditions that
/// pause nothing may expire, and a dead app's conditions then free the wallpaper.
nonisolated public struct ConditionsFolder: Equatable, Sendable {
    private struct Sensed: Equatable, Sendable {
        var covered: Set<DisplayIdentity> = []
        var asleep: Set<DisplayIdentity> = []
        var locked = false
        var power = PowerState()
    }

    public static let refreshInterval = PlaybackConditions.expiry / 2

    public private(set) var rules: PauseRules
    public let host: HostCapabilities
    /// The conditions given last, if any.
    public private(set) var latest: SensedConditions?
    /// When the owner should send the next `.tick`; `nil` while nothing would pause.
    public private(set) var nextRefresh: Date?

    private var displays: Set<DisplayIdentity> = []
    private var sensed = Sensed()

    public init(rules: PauseRules = PauseRules(), host: HostCapabilities = HostCapabilities(showsLockScreen: true)) {
        self.rules = rules
        self.host = host
    }

    /// New conditions when the event changed what is sensed or a refresh is due, otherwise `nil`.
    public mutating func fold(_ event: SensorEvent, at now: Date) -> SensedConditions? {
        let before = sensed
        switch event {
        case .displays(let connected): displays = connected
        case .covered(let covered): sensed.covered = covered
        case .asleep(let asleep): sensed.asleep = asleep
        case .locked(let locked): sensed.locked = locked
        case .power(let power): sensed.power = power
        case .rules(let rules): self.rules = rules
        case .tick: break
        }

        let pausing = wouldPause(at: now)
        var given: SensedConditions?
        if sensed != before || (pausing && isRefreshDue(at: now)) {
            given = conditions(at: now)
            latest = given
        }
        nextRefresh = pausing ? latest.map { $0.sensedAt + Self.refreshInterval } : nil
        return given
    }

    private func isRefreshDue(at now: Date) -> Bool {
        guard let latest else { return true }
        return now.timeIntervalSince(latest.sensedAt) >= Self.refreshInterval.timeInterval
    }

    private func wouldPause(at now: Date) -> Bool {
        displays.union(sensed.covered).union(sensed.asleep).contains { display in
            let conditions = PlaybackConditions(
                desktopCovered: sensed.covered.contains(display),
                displayAsleep: sensed.asleep.contains(display),
                displayLocked: sensed.locked,
                lowPowerMode: sensed.power.lowPowerMode,
                onBattery: sensed.power.onBattery,
                sensedAt: now,
                now: now
            )
            return decidePlayback(conditions, rules: rules, host: host) != .play
        }
    }

    private func conditions(at now: Date) -> SensedConditions {
        SensedConditions(
            sensedAt: now,
            coveredDisplays: sensed.covered,
            asleepDisplays: sensed.asleep,
            locked: sensed.locked,
            lowPowerMode: sensed.power.lowPowerMode,
            onBattery: sensed.power.onBattery
        )
    }
}
