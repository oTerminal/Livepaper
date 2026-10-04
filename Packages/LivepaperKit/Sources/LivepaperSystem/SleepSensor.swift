import AppKit

/// The Mac going to sleep, and waking.
nonisolated public enum SystemSleepEvent: Equatable, Sendable {
    case willSleep
    case didWake
}

/// The Mac's sleep and wake, as events.
public protocol SleepSensor: AnyObject {
    /// Each sleep and each wake from now on. There is no current value.
    func updates() -> AsyncStream<SystemSleepEvent>
}

/// Listens for the workspace's sleep and wake notifications.
public final class SystemSleepSensor: SleepSensor {
    private let broadcast = Broadcast<SystemSleepEvent>(replaysLatest: false, bufferingPolicy: .unbounded)
    private let triggers = NotificationTriggers()

    public init() {
        broadcast.whenRead(start: { [weak self] in self?.start() }, stop: { [weak self] in self?.triggers.stop() })
    }

    public func updates() -> AsyncStream<SystemSleepEvent> {
        broadcast.stream()
    }

    private func start() {
        let willSleep = NSWorkspace.willSleepNotification
        triggers.start([.workspace(willSleep), .workspace(NSWorkspace.didWakeNotification)]) { [weak self] name in
            self?.broadcast.send(name == willSleep ? .willSleep : .didWake)
        }
    }
}
