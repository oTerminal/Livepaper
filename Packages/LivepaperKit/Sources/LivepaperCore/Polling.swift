import Foundation

/// Looking at a condition now and then until it holds, for a while at most: a
/// command that arrives before the launch has read the library and the
/// displays waits for them so, and is answered when the wait is up.
public enum Polling {
    /// Whether `holds` came true, looked at every `interval` on `clock`, within
    /// `limit`, or for as long as it takes when that is nil. False once the
    /// task is cancelled.
    public static func wait<C: Clock<Duration>>(
        until holds: () -> Bool, every interval: Duration, within limit: Duration?, clock: C
    ) async -> Bool {
        let deadline = limit.map { clock.now.advanced(by: $0) }
        while !holds() {
            if let deadline, clock.now >= deadline { return false }
            do {
                try await clock.sleep(for: interval)
            } catch {
                return false
            }
        }
        return true
    }
}
