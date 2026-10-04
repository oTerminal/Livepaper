import Foundation
import LivepaperCore
import os

/// Moves each display's playlist on: at the end of its interval, when the Mac
/// wakes, and once a session at login.
///
/// What rotation remembers is the app state's `rotation`, loaded with the rest
/// of `app-state.json`: there is no second file. The decisions are
/// `RotationSchedule`'s. The driver holds the one timer, set for the earliest
/// end of an interval among the displays rotation moves, listens for the wake,
/// and hands each new state to `commit`, which the app model supplies; it
/// writes nothing itself. The model tells it of every change to the state, the
/// connected displays or Pause All through `update`, the states it committed
/// for the driver included, and the timer is set again from them.
public final class RotationDriver {
    /// When the timer fires next; nil while none is set.
    public private(set) var nextTick: Date?

    private let clock: any WallClock
    private let sleep: any SleepSensor
    private var rng: any RandomNumberGenerator
    private let logger: Logger
    private let commit: (AppState) -> Void
    /// Nil until the launch, and again after a stop.
    private var schedule: RotationSchedule?
    private var timer: ScheduledCall?
    /// When a tick last moved nothing. A timer can fire a hair before its
    /// moment and find nothing due; it is then set again, for later than this.
    private var emptyTick: Date?
    private var sleepWatch: Task<Void, Never>?

    /// - Parameters:
    ///   - sleep: the wakes, from the sleep sensor.
    ///   - rng: the order of a shuffled pass.
    ///   - commit: makes the change, and then calls `update` with what the model holds.
    public init(
        clock: any WallClock = SystemWallClock(),
        sleep: any SleepSensor = SystemSleepSensor(),
        rng: any RandomNumberGenerator = SystemRandomNumberGenerator(),
        logger: Logger = Logger(subsystem: LivepaperSystem.logSubsystem, category: RotationLog.category),
        commit: @escaping (AppState) -> Void
    ) {
        self.clock = clock
        self.sleep = sleep
        self.rng = rng
        self.logger = logger
        self.commit = commit
    }

    /// Once, when the app state is loaded and the connected displays are
    /// first known. The displays that last rotated before the session started
    /// rotate with `.login`; a relaunch in the same session finds their last
    /// rotation after the start and rotates nothing. With no `sessionStart`
    /// nothing rotates at launch. Then the timer is set and wakes are heard.
    public func launch(state: AppState, connected: [DisplayIdentity], isPausedAll: Bool, sessionStart: Date?) {
        guard schedule == nil else { return update(state: state, connected: connected, isPausedAll: isPausedAll) }
        var schedule = RotationSchedule(state: state, connected: connected, isPausedAll: isPausedAll)
        let now = clock.now
        let change: RotationChange?
        if let sessionStart {
            change = schedule.login(sessionStart: sessionStart, at: now, rng: &rng)
            logger.notice("\(RotationLog.login(sessionStart: sessionStart, rotated: change?.rotated ?? []), privacy: .public)")
        } else {
            change = schedule.change(state: state, connected: connected, isPausedAll: isPausedAll, at: now)
        }
        self.schedule = schedule
        watchSleep()
        apply(change, at: now)
    }

    /// The app state, the connected displays or Pause All changed. A display
    /// a pause let go counts its interval from now; the timer is set again.
    /// Nothing happens before the launch.
    public func update(state: AppState, connected: [DisplayIdentity], isPausedAll: Bool) {
        guard var schedule else { return }
        let now = clock.now
        let change = schedule.change(state: state, connected: connected, isPausedAll: isPausedAll, at: now)
        self.schedule = schedule
        apply(change, at: now)
    }

    /// At quit: the timer goes, wakes are no longer heard, and nothing rotates until the next launch.
    public func stop() {
        timer?.cancel()
        timer = nil
        nextTick = nil
        emptyTick = nil
        sleepWatch?.cancel()
        sleepWatch = nil
        schedule = nil
    }

    // MARK: Events

    private func tickDue() {
        timer = nil
        nextTick = nil
        guard var schedule else { return }
        let now = clock.now
        let change = schedule.tick(at: now, rng: &rng)
        self.schedule = schedule
        if let rotated = change?.rotated, !rotated.isEmpty {
            logger.notice("\(RotationLog.rotated(.tick, rotated), privacy: .public)")
        } else {
            emptyTick = now
        }
        apply(change, at: now)
    }

    private func woke() {
        guard var schedule else { return }
        let now = clock.now
        let change = schedule.wake(at: now, rng: &rng)
        self.schedule = schedule
        logger.notice("\(RotationLog.rotated(.wake, change?.rotated ?? []), privacy: .public)")
        apply(change, at: now)
    }

    private func watchSleep() {
        sleepWatch?.cancel()
        let events = sleep.updates()
        sleepWatch = Task { [weak self] in
            for await event in events where event == .didWake {
                self?.woke()
            }
        }
    }

    /// Commits a change, then sets the timer. The schedule already holds the
    /// change, so the `update` that the commit brings changes nothing more.
    private func apply(_ change: RotationChange?, at now: Date) {
        if let change {
            if !change.counting.isEmpty {
                logger.notice("\(RotationLog.counting(change.counting, from: now), privacy: .public)")
            }
            commit(change.state)
        }
        setTimer()
    }

    private func setTimer() {
        var due = schedule?.nextTick
        if let set = due, let emptyTick, set <= emptyTick {
            // The schedule sets the timer for a moment that finds an interval
            // passed, so this is a fault; a timer set again for it would fire
            // at once, over and over. It waits for the next change instead.
            logger.error("\(RotationLog.tickMovedNothing, privacy: .public)")
            due = nil
        }
        guard due != nextTick else { return }
        timer?.cancel()
        timer = nil
        nextTick = due
        logger.notice("\(RotationLog.nextTick(due), privacy: .public)")
        guard let due else { return }
        timer = clock.schedule(at: due) { [weak self] in self?.tickDue() }
    }
}

/// The wording of the rotation driver's log lines, under
/// `LivepaperSystem.logSubsystem`, category `rotation`. The rotation check
/// reads them: that a display rotates at the interval, on wake and once at
/// login, and not on a relaunch or while paused.
nonisolated public enum RotationLog {
    public static let category = "rotation"

    public enum Event: String, Sendable {
        case tick
        case wake
    }

    public static func login(sessionStart: Date, rotated: [DisplayIdentity]) -> String {
        "rotation: session started \(sessionStart.formatted(.iso8601)), login rotated \(list(rotated))"
    }

    public static func rotated(_ event: Event, _ displays: [DisplayIdentity]) -> String {
        "rotation: \(event.rawValue) rotated \(list(displays))"
    }

    public static func counting(_ displays: [DisplayIdentity], from date: Date) -> String {
        "rotation: \(list(displays)) \(displays.count == 1 ? "counts" : "count") from \(date.formatted(.iso8601))"
    }

    public static func nextTick(_ date: Date?) -> String {
        date.map { "rotation: next tick at \($0.formatted(.iso8601))" } ?? "rotation: no tick due"
    }

    public static let tickMovedNothing = "rotation: a tick moved nothing and would be due again at once; no tick until the next change"

    private static func list(_ displays: [DisplayIdentity]) -> String {
        displays.isEmpty ? "nothing" : displays.map(\.description).joined(separator: ", ")
    }
}
