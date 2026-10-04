import Foundation
import LivepaperCore
import os

/// Reads the sensors, folds what they report through a `ConditionsFolder`, and
/// hands each new `SensedConditions` to `onChange`. The owner puts it into the
/// next render state and applies that.
///
/// The folder's refresh, while something would pause a display, is one timer
/// on the clock; nothing else runs while nothing changes.
public final class ConditionsSensing {
    public let displays: any DisplaySensor
    public let power: any PowerSensor
    public let lock: any LockSensor
    public let displaySleep: any DisplaySleepSensor
    public let covered: any CoveredDisplaySensor

    /// The displays connected now, as the display sensor last said.
    public private(set) var connectedDisplays: [ConnectedDisplay] = []
    /// The conditions handed on last.
    public var latest: SensedConditions? { folder.latest }
    public var isRunning: Bool { !watches.isEmpty }

    /// The user's pause rules. Changing them can hand the conditions on again at
    /// once, and tells the covered-display sensor whether covering pauses.
    public var rules: PauseRules {
        get { folder.rules }
        set {
            covered.coveringPauses = newValue.whenDesktopCovered
            fold(.rules(newValue))
        }
    }

    private var folder: ConditionsFolder
    private let clock: any WallClock
    private let logger: Logger
    private let onChange: @MainActor (SensedConditions) -> Void
    private var watches: [Task<Void, Never>] = []
    private var refresh: ScheduledCall?
    private var refreshAt: Date?

    /// - Parameter host: what the render host can do; the extension shows the lock screen.
    public init(
        rules: PauseRules,
        host: HostCapabilities = HostCapabilities(showsLockScreen: true),
        displays: any DisplaySensor = SystemDisplaySensor(),
        power: any PowerSensor = SystemPowerSensor(),
        lock: any LockSensor = SystemLockSensor(),
        displaySleep: any DisplaySleepSensor = SystemDisplaySleepSensor(),
        covered: any CoveredDisplaySensor = SystemCoveredDisplaySensor(),
        clock: any WallClock = SystemWallClock(),
        logger: Logger = Logger(subsystem: LivepaperSystem.logSubsystem, category: SensingLog.category),
        onChange: @escaping @MainActor (SensedConditions) -> Void
    ) {
        folder = ConditionsFolder(rules: rules, host: host)
        self.displays = displays
        self.power = power
        self.lock = lock
        self.displaySleep = displaySleep
        self.covered = covered
        self.clock = clock
        self.logger = logger
        self.onChange = onChange
        covered.coveringPauses = rules.whenDesktopCovered
    }

    public func start() {
        guard watches.isEmpty else { return }
        watches = [
            watch(displays.updates()) { sensing, displays in
                sensing.connectedDisplays = displays
                sensing.fold(.displays(Set(displays.map(\.identity))))
            },
            watch(power.updates()) { $0.fold(.power($1)) },
            watch(lock.updates()) { $0.fold(.locked($1)) },
            watch(displaySleep.updates()) { $0.fold(.asleep($1)) },
            watch(covered.updates()) { $0.fold(.covered($1)) },
        ]
    }

    /// Stops reading the sensors, which then stop observing the system, and stops the refresh.
    public func stop() {
        for watch in watches {
            watch.cancel()
        }
        watches = []
        refresh?.cancel()
        refresh = nil
        refreshAt = nil
    }

    private func watch<Value: Sendable>(
        _ updates: AsyncStream<Value>,
        _ handle: @escaping (ConditionsSensing, Value) -> Void
    ) -> Task<Void, Never> {
        Task { [weak self] in
            for await value in updates {
                guard let self else { return }
                handle(self, value)
            }
        }
    }

    private func fold(_ event: SensorEvent) {
        let previous = folder.latest
        if let conditions = folder.fold(event, at: clock.now) {
            // A change is kept in the log; a refresh of the same conditions every 15 s is not.
            var unchanged = previous
            unchanged?.sensedAt = conditions.sensedAt
            if unchanged == conditions {
                logger.debug("\(SensingLog.conditions(conditions), privacy: .public)")
            } else {
                logger.notice("\(SensingLog.conditions(conditions), privacy: .public)")
            }
            onChange(conditions)
        }
        armRefresh()
    }

    private func armRefresh() {
        let next = isRunning ? folder.nextRefresh : nil
        guard next != refreshAt else { return }
        refresh?.cancel()
        refresh = nil
        refreshAt = next
        guard let next else { return }
        refresh = clock.schedule(at: next) { [weak self] in
            self?.refreshDue()
        }
    }

    private func refreshDue() {
        refresh = nil
        refreshAt = nil
        fold(.tick)
    }
}
