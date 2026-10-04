import Foundation

/// The status line's Restart, from the click to what came of it.
///
/// A click asks the render host to restart WallpaperAgent, which it refuses
/// within `agentRestartGap` of the last restart, whoever asked for that one.
/// While the host works the line says so; after a restart it waits for the
/// service to answer, for as long as the extension has to send its first
/// heartbeat; after a refusal, or a restart the service did not answer in
/// that time, it says when Restart can next be tried. Once the service
/// answers, or that time comes, the host's own status has the line again.
public struct ServiceRestart: Equatable, Sendable {
    /// How long the line waits for the service after a restart: the grace the
    /// extension has to send its first heartbeat.
    public static let answerWait: Duration = HeartbeatTiming.standard.grace

    public enum Phase: Equatable, Sendable {
        case idle
        /// The host is restarting WallpaperAgent, or deciding not to.
        case restarting
        /// WallpaperAgent was restarted; the line waits until `until` for the
        /// service to answer. `retryFrom` is when another restart may be made.
        case waitingForAnswer(until: Date, retryFrom: Date)
        /// Restart cannot be tried again until then.
        case retryFrom(Date)
    }

    public private(set) var phase: Phase = .idle

    public init() {}

    /// Restart was clicked. Answers false while a restart is running: a second
    /// click is not a second restart.
    public mutating func started() -> Bool {
        guard phase != .restarting else { return false }
        phase = .restarting
        return true
    }

    /// The host has answered the request. `before` and `after` are its last
    /// restart of WallpaperAgent on either side of it: a new one is the restart
    /// made, the same one a refusal.
    public mutating func finished(lastRestartBefore before: Date?, after: Date?, at now: Date) {
        guard phase == .restarting else { return }
        guard let after else {
            phase = .idle
            return
        }
        let retryFrom = after + agentRestartGap
        phase = after == before ? .retryFrom(retryFrom) : .waitingForAnswer(until: now + Self.answerWait, retryFrom: retryFrom)
    }

    /// The host's status changed. A service that answers, whatever it says,
    /// no longer needs Restart.
    public mutating func hostChanged(to status: RenderHostStatus) {
        guard phase != .restarting, status != .recovering(.restartAgent) else { return }
        phase = .idle
    }

    /// The wait for an answer ends in when Restart can next be tried, and that ends at its time.
    public mutating func tick(at now: Date) {
        switch phase {
        case .waitingForAnswer(let until, let retryFrom) where now >= until:
            phase = retryFrom > now ? .retryFrom(retryFrom) : .idle
        case .retryFrom(let date) where now >= date:
            phase = .idle
        case .idle, .restarting, .waitingForAnswer, .retryFrom:
            break
        }
    }

    /// When a tick next has something to do, for the caller to schedule one.
    public var nextTick: Date? {
        switch phase {
        case .waitingForAnswer(let until, _): until
        case .retryFrom(let date): date
        case .idle, .restarting: nil
        }
    }
}
