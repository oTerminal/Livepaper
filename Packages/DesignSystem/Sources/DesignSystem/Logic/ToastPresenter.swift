import Foundation

/// What a toast says. `undoTitle` makes it an undo toast.
public nonisolated struct ToastItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var message: String
    public var systemImage: String?
    public var undoTitle: String?

    public init(id: UUID = UUID(), message: String, systemImage: String? = nil, undoTitle: String? = nil) {
        self.id = id
        self.message = message
        self.systemImage = systemImage
        self.undoTitle = undoTitle
    }
}

/// Holds the one toast on screen. A new toast replaces the current one in place;
/// nothing queues, so the screen never lags behind what the user just did.
public nonisolated struct ToastPresenter: Equatable, Sendable {
    public enum Event: Sendable {
        case show(ToastItem)
        case undo
        /// The toast with this identifier ran out of time. Ignored once that
        /// toast has been replaced.
        case expire(ToastItem.ID)
        case dismiss
    }

    public enum Effect: Equatable, Sendable {
        /// Undo what the toast with this identifier reported.
        case undo(ToastItem.ID)
    }

    /// How long a toast stays without the pointer over it.
    public static var lifetime: Duration { .seconds(5) }

    public private(set) var current: ToastItem?

    public init() {}

    @discardableResult
    public mutating func send(_ event: Event) -> Effect? {
        switch event {
        case .show(let item):
            current = item
            return nil
        case .undo:
            guard let current, current.undoTitle != nil else { return nil }
            self.current = nil
            return .undo(current.id)
        case .expire(let id):
            if current?.id == id {
                current = nil
            }
            return nil
        case .dismiss:
            current = nil
            return nil
        }
    }
}
