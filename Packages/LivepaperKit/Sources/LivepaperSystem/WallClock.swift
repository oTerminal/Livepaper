import Dispatch
import Foundation

/// The time of day, and one-shot calls at a time of day. Injected, so that
/// tests move time by hand and nothing here reads the real clock in them.
///
/// Times are wall-clock times because the host's judgements are: a call due
/// while the Mac slept runs as soon as it wakes.
public protocol WallClock: AnyObject {
    var now: Date { get }
    /// Calls `action` once at `date`, or at once if `date` has passed, unless
    /// the returned call is cancelled first.
    func schedule(at date: Date, _ action: @escaping @MainActor () -> Void) -> ScheduledCall
}

/// A call a `WallClock` will make, until it is cancelled.
public final class ScheduledCall {
    private var onCancel: (() -> Void)?

    public init(onCancel: @escaping () -> Void) {
        self.onCancel = onCancel
    }

    public func cancel() {
        onCancel?()
        onCancel = nil
    }
}

/// The real clock: a dispatch timer on the main queue with a wall-clock deadline.
public final class SystemWallClock: WallClock {
    public init() {}

    public var now: Date { Date() }

    public func schedule(at date: Date, _ action: @escaping @MainActor () -> Void) -> ScheduledCall {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        let seconds = date.timeIntervalSince1970.rounded(.down)
        let deadline = DispatchWallTime(
            timespec: timespec(tv_sec: Int(seconds), tv_nsec: Int((date.timeIntervalSince1970 - seconds) * 1_000_000_000))
        )
        timer.schedule(wallDeadline: deadline, leeway: .milliseconds(100))
        timer.setEventHandler {
            MainActor.assumeIsolated {
                timer.cancel()
                action()
            }
        }
        timer.activate()
        return ScheduledCall { timer.cancel() }
    }
}
