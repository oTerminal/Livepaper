import Foundation

/// Lets calls through to what it guards until it is closed, and none after.
///
/// An engine is retired from another thread, and a read may be blocking the engine's queue at
/// that moment and return at any time after it. So every call an engine makes on its layer's
/// renderer or clock goes through `pass`, under a lock that `close` takes too: once `close`
/// has returned, no call is under way and none will start.
///
/// `@unchecked Sendable` because what it guards is not Sendable. It holds because `guarded` is
/// read and written only with `lock` held, handed to a body that runs to its end under the
/// lock, and let go at `close`. A body must not keep what it is handed, and must not pass
/// through the same gate again: the lock is not recursive.
final class RetirementGate<Guarded>: @unchecked Sendable {
    private let lock = NSLock()
    private var guarded: Guarded?

    init(_ guarded: Guarded) {
        self.guarded = guarded
    }

    var isClosed: Bool {
        lock.withLock { guarded == nil }
    }

    /// Runs `body` on what the gate guards, unless the gate has closed: then nil, and `body`
    /// does not run.
    @discardableResult
    func pass<Value>(_ body: (inout Guarded) -> Value) -> Value? {
        lock.withLock {
            guard guarded != nil else { return nil }
            return body(&guarded!)
        }
    }

    /// Closes the gate for good, once a call under way has finished. `last` is the one call
    /// after it; closing again does nothing.
    func close(_ last: (inout Guarded) -> Void = { _ in }) {
        lock.withLock {
            guard guarded != nil else { return }
            last(&guarded!)
            guarded = nil
        }
    }
}
