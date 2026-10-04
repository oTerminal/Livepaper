/// Decides which wallpaper tile, if any, shows its live preview. The pointer has
/// to rest on a tile for `dwell` first, so sweeping across the grid starts
/// nothing, and `live` being one value means two tiles are never live at once.
public nonisolated struct HoverDwell<ID: Hashable, Instant: InstantProtocol> where Instant.Duration == Duration {
    public enum Event {
        case enter(ID)
        case exit(ID)
        /// Time has passed. Send one at `deadline`.
        case tick
    }

    public static var dwell: Duration { .milliseconds(200) }

    /// The tile showing its live preview.
    public private(set) var live: ID?
    /// Off under Reduce Motion: no hover autoplay.
    public var isEnabled: Bool {
        didSet {
            if !isEnabled {
                live = nil
                waiting = nil
            }
        }
    }

    private var waiting: (id: ID, since: Instant)?

    public init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    /// When the waiting tile is due to go live, if one is waiting.
    public var deadline: Instant? {
        waiting.map { $0.since.advanced(by: Self.dwell) }
    }

    public mutating func send(_ event: Event, at now: Instant) {
        guard isEnabled else { return }
        switch event {
        case .enter(let id):
            if live != id {
                waiting = (id, now)
            }
        case .exit(let id):
            if waiting?.id == id {
                waiting = nil
            }
            if live == id {
                live = nil
            }
        case .tick:
            if let waiting, let deadline, now >= deadline {
                live = waiting.id
                self.waiting = nil
            }
        }
    }
}

extension HoverDwell: Sendable where ID: Sendable {}
extension HoverDwell.Event: Sendable where ID: Sendable {}
