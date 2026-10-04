/// How an engine answers trouble on its layer: a renderer that failed or asks for a flush, or a
/// reader that broke. It starts again from a fresh reader, since the one in hand is mid-GOP.
///
/// The renderer reports one trouble in two ways, by notification and in its pull callback, and
/// it is answered once: nothing more is answered until a start feeds the layer again. After
/// `limit` restarts with no loop completed between them the engine gives up, and leaves the next
/// step to the watchdog.
struct TroubleResponse: Equatable, Sendable {
    enum Answer: Equatable, Sendable {
        case restart
        /// Already answered: a restart is coming, or the engine gave up.
        case ignore
        case giveUp
    }

    static let limit = 3

    private var restartsWithoutLoop = 0
    private var answered = false

    mutating func trouble() -> Answer {
        guard !answered else { return .ignore }
        answered = true
        restartsWithoutLoop += 1
        return restartsWithoutLoop <= Self.limit ? .restart : .giveUp
    }

    /// A start put its first frame on the layer and feeds it: trouble from here on is new.
    mutating func feeding() {
        answered = false
    }

    mutating func loopCompleted() {
        restartsWithoutLoop = 0
    }
}
