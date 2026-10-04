import Foundation

/// What the Set on Display button shows: working until the render state is
/// applied, done for 1.5 s, then idle again.
public struct SetOnDisplayFeedback: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle, working, done
    }

    public static let doneDuration: Duration = .milliseconds(1500)

    public private(set) var phase: Phase
    /// When done gives way to idle; the caller schedules a tick for it.
    public private(set) var idleAt: Date?

    public init() {
        phase = .idle
        idleAt = nil
    }

    public mutating func started() {
        phase = .working
        idleAt = nil
    }

    /// The set is saved and on the displays, paused there under Pause All.
    /// Only a set that is working can be done.
    public mutating func applied(at now: Date) {
        guard phase == .working else { return }
        phase = .done
        idleAt = now.addingTimeInterval(Self.doneDuration / .seconds(1))
    }

    /// The set was refused, as every change is while the library cannot be
    /// read: nothing was saved, so it is never done.
    public mutating func refused() {
        guard phase == .working else { return }
        phase = .idle
        idleAt = nil
    }

    public mutating func tick(at now: Date) {
        guard phase == .done, let idleAt, now >= idleAt else { return }
        phase = .idle
        self.idleAt = nil
    }
}
