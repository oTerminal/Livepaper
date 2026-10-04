import AppKit

/// Observes a set of notifications, from any of the system's notification
/// centres, and calls one handler on the main actor with the name of the one
/// that arrived.
final class NotificationTriggers {
    struct Trigger {
        let center: NotificationCenter
        let name: Notification.Name

        static func workspace(_ name: Notification.Name) -> Trigger {
            Trigger(center: NSWorkspace.shared.notificationCenter, name: name)
        }

        static func application(_ name: Notification.Name) -> Trigger {
            Trigger(center: .default, name: name)
        }

        /// Posted by the system to every process in the session.
        static func distributed(_ name: String) -> Trigger {
            Trigger(center: DistributedNotificationCenter.default(), name: Notification.Name(name))
        }
    }

    private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []

    func start(_ triggers: [Trigger], _ handler: @escaping @MainActor (Notification.Name) -> Void) {
        stop()
        observers = triggers.map { trigger in
            let name = trigger.name
            let token = trigger.center.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { handler(name) }
            }
            return (trigger.center, token)
        }
    }

    func stop() {
        for observer in observers {
            observer.center.removeObserver(observer.token)
        }
        observers = []
    }
}
