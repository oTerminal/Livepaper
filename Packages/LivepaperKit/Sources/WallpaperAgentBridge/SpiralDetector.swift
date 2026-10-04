import Foundation
import LivepaperCore

/// Tells a wedged WallpaperAgent from a working one by the connections it makes.
///
/// A connection that ends without the agent calling anything is the signature of
/// an agent reconnecting in a loop. Four of those in a
/// row signal, at most once per `agentRestartGap` on the clock, and the app restarts
/// the agent: the sandbox keeps the extension from doing it. A connection that
/// was served resets the count.
public struct SpiralDetector: Equatable, Sendable {
    /// Empty connections in a row that signal.
    public static let emptyConnectionsThatSignal = 4

    public private(set) var emptyInARow = 0
    public private(set) var lastSignal: Date?
    /// Whether no connection has been served since the last signal.
    private var unanswered = false

    public init() {}

    /// Records a connection that ended. Returns whether the app should now be
    /// asked to restart WallpaperAgent.
    public mutating func connectionEnded(served: Bool, at now: Date) -> Bool {
        guard !served else {
            emptyInARow = 0
            unanswered = false
            return false
        }
        emptyInARow += 1
        guard emptyInARow >= Self.emptyConnectionsThatSignal,
              allowAgentRestart(last: lastSignal, now: now) else { return false }
        lastSignal = now
        unanswered = true
        return true
    }

    /// Whether the heartbeat should carry `spiralDetected`: from a signal until
    /// a connection is served or `agentRestartGap` passes. The app acts on the flag
    /// through `allowAgentRestart`, so holding it up cannot restart the agent
    /// twice; taking it down after the gap stops a flag that nobody acted on
    /// (no app running) from standing for good, and a spiral that goes on
    /// signals again then.
    public func isSignalling(at now: Date) -> Bool {
        guard unanswered, let lastSignal else { return false }
        return now.timeIntervalSince(lastSignal) < agentRestartGap / .seconds(1)
    }
}
