import Dispatch
import LivepaperCore

/// Posts and observes the Darwin notifications between the app and the
/// extension. Injected, so that tests leave alone the real notify centre,
/// which every process on the Mac shares.
public protocol DarwinNotifying: AnyObject {
    func post(_ notification: DarwinNotification, state: UInt64?)
    /// Calls `handler` with the state each time `notification` is posted, until
    /// `stopObserving`. Returns `false` when it cannot observe.
    func observe(_ notification: DarwinNotification, _ handler: @escaping @MainActor (UInt64) -> Void) -> Bool
    func stopObserving(_ notification: DarwinNotification)
}

/// The notify centre, observed on the main queue.
public final class DarwinNotifier: DarwinNotifying {
    private var observations: [DarwinNotification: DarwinObservation] = [:]

    public init() {}

    public func post(_ notification: DarwinNotification, state: UInt64?) {
        notification.post(state: state)
    }

    public func observe(_ notification: DarwinNotification, _ handler: @escaping @MainActor (UInt64) -> Void) -> Bool {
        stopObserving(notification)
        let observation = notification.observe(on: .main) { state in
            MainActor.assumeIsolated { handler(state) }
        }
        observations[notification] = observation
        return observation != nil
    }

    public func stopObserving(_ notification: DarwinNotification) {
        observations.removeValue(forKey: notification)?.cancel()
    }
}
