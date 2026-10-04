import Foundation
import Synchronization

/// A clock that moves only when a test moves it, with a wall clock that moves
/// along: `date` is `start` plus the time advanced. A sleeper wakes when
/// `advance` reaches its deadline, or throws when its task is cancelled.
public final class ManualClock: Clock, Sendable {
    public struct Instant: InstantProtocol, CustomStringConvertible {
        /// The time advanced since the clock was made.
        public var offset: Duration

        public init(offset: Duration) {
            self.offset = offset
        }

        public func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        public func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        public static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }

        public var description: String { "\(offset)" }
    }

    private struct Sleeper {
        let deadline: Instant
        let continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now = Instant(offset: .zero)
        var sleepers: [Int: Sleeper] = [:]
        var lastToken = 0
    }

    private let state = Mutex(State())

    /// The wall-clock time when the clock was made.
    public let start: Date

    public init(start: Date) {
        self.start = start
    }

    public var now: Instant { state.withLock { $0.now } }

    public var minimumResolution: Duration { .zero }

    /// The wall-clock time now.
    public var date: Date { start.addingTimeInterval(now.offset / .seconds(1)) }

    /// How many sleepers are waiting for the clock to move.
    public var sleeperCount: Int { state.withLock { $0.sleepers.count } }

    public func sleep(until deadline: Instant, tolerance: Duration? = nil) async throws {
        let token = state.withLock { state in
            state.lastToken += 1
            return state.lastToken
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                let outcome: Result<Void, any Error>? = state.withLock { state in
                    if Task.isCancelled { return .failure(CancellationError()) }
                    if deadline <= state.now { return .success(()) }
                    state.sleepers[token] = Sleeper(deadline: deadline, continuation: continuation)
                    return nil
                }
                if let outcome { continuation.resume(with: outcome) }
            }
        } onCancel: {
            let sleeper = state.withLock { $0.sleepers.removeValue(forKey: token) }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves the clock on, waking every sleeper whose deadline it reaches, earliest first.
    public func advance(by duration: Duration) {
        let due = state.withLock { state in
            state.now = state.now.advanced(by: duration)
            let now = state.now
            let due = state.sleepers.filter { $0.value.deadline <= now }
            for token in due.keys { state.sleepers[token] = nil }
            return due.values.sorted { $0.deadline < $1.deadline }
        }
        for sleeper in due { sleeper.continuation.resume() }
    }

    /// Moves the clock on to a wall-clock time.
    public func advance(to date: Date) {
        advance(by: .seconds(date.timeIntervalSince(self.date)))
    }
}
