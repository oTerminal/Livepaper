import AppKit
import CoreGraphics
import LivepaperCore

/// Which connected displays are asleep.
public protocol DisplaySleepSensor: AnyObject {
    /// The sleeping displays now, and again each time that changes.
    func updates() -> AsyncStream<Set<DisplayIdentity>>
}

/// Asks CoreGraphics which displays are asleep whenever the workspace says the
/// screens slept or woke, the Mac woke, or the displays were reconfigured.
public final class SystemDisplaySleepSensor: DisplaySleepSensor {
    private let broadcast = Broadcast<Set<DisplayIdentity>>()
    private let triggers = NotificationTriggers()

    public init() {
        broadcast.whenRead(start: { [weak self] in self?.start() }, stop: { [weak self] in self?.triggers.stop() })
    }

    public func updates() -> AsyncStream<Set<DisplayIdentity>> {
        broadcast.stream()
    }

    private func start() {
        let screensDidSleep = NSWorkspace.screensDidSleepNotification
        let triggerList: [NotificationTriggers.Trigger] = [
            .workspace(screensDidSleep),
            .workspace(NSWorkspace.screensDidWakeNotification),
            .workspace(NSWorkspace.didWakeNotification),
            .application(NSApplication.didChangeScreenParametersNotification),
        ]
        triggers.start(triggerList) { [weak self] name in
            // The notification can come before each display reports itself asleep.
            self?.send(name == screensDidSleep ? Self.allDisplays() : Self.asleepNow())
        }
        broadcast.send(Self.asleepNow())
    }

    private func send(_ asleep: Set<DisplayIdentity>) {
        if asleep != broadcast.latest { broadcast.send(asleep) }
    }

    private static func allDisplays() -> Set<DisplayIdentity> {
        Set(ConnectedDisplays.current().map(\.identity))
    }

    private static func asleepNow() -> Set<DisplayIdentity> {
        Set(ConnectedDisplays.current().filter { CGDisplayIsAsleep($0.displayID) != 0 }.map(\.identity))
    }
}
