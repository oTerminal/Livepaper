import Darwin
import Dispatch
import notify
import Synchronization

/// A Darwin notification: a name any process may post, carrying 64 bits of
/// state. It works in both directions from inside the extension's sandbox.
public struct DarwinNotification: Hashable, Sendable, CustomStringConvertible {
    public let name: String

    public init(_ name: String) {
        self.name = name
    }

    public var description: String { name }

    /// Sets the state, if one is given, and then posts, so that an observer
    /// woken by the post reads the new state.
    public func post(state: UInt64? = nil) {
        if let state, let token = Self.stateToken(for: name) {
            notify_set_state(token, state)
        }
        notify_post(name)
    }

    /// The state last set by any process, or `nil` when it cannot be read.
    public func currentState() -> UInt64? {
        guard let token = Self.stateToken(for: name) else { return nil }
        var state: UInt64 = 0
        return notify_get_state(token, &state) == UInt32(NOTIFY_STATUS_OK) ? state : nil
    }

    /// Calls `handler` on `queue` with the state each time the notification is
    /// posted, until the observation is cancelled or released.
    public func observe(on queue: DispatchQueue, _ handler: @escaping @Sendable (UInt64) -> Void) -> DarwinObservation? {
        var token: Int32 = 0
        let status = notify_register_dispatch(name, &token, queue) { token in
            var state: UInt64 = 0
            notify_get_state(token, &state)
            handler(state)
        }
        return status == UInt32(NOTIFY_STATUS_OK) ? DarwinObservation(token: token) : nil
    }

    /// One token per name for the life of the process. notifyd keeps a name's
    /// state while a token for it is registered, so these are never cancelled.
    private static let stateTokens = Mutex<[String: Int32]>([:])

    private static func stateToken(for name: String) -> Int32? {
        stateTokens.withLock { tokens in
            if let token = tokens[name] { return token }
            var token: Int32 = 0
            guard notify_register_check(name, &token) == UInt32(NOTIFY_STATUS_OK) else { return nil }
            tokens[name] = token
            return token
        }
    }
}

/// An observation of a Darwin notification. Released or cancelled, it stops.
public final class DarwinObservation: Sendable {
    private let token: Mutex<Int32?>

    init(token: Int32) {
        self.token = Mutex(token)
    }

    public func cancel() {
        token.withLock { token in
            if let registered = token { notify_cancel(registered) }
            token = nil
        }
    }

    deinit {
        cancel()
    }
}
