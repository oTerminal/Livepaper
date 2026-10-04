import Foundation
import Testing
import WallpaperAgentBridge

struct SpiralDetectorTests {
    /// One connection ending: whether the agent called anything on it, and when.
    struct Ending: Sendable {
        var served: Bool
        var at: TimeInterval

        static func empty(_ at: TimeInterval) -> Ending { Ending(served: false, at: at) }
        static func served(_ at: TimeInterval) -> Ending { Ending(served: true, at: at) }
    }

    /// Which endings (by index) signal.
    static let rows: [Row<[Ending], [Int]>] = [
        Row("three empty connections do not signal", [.empty(0), .empty(1), .empty(2)], []),
        Row("four empty connections in a row signal on the fourth", [.empty(0), .empty(1), .empty(2), .empty(3)], [3]),
        Row(
            "a served connection resets the count",
            [.empty(0), .empty(1), .empty(2), .served(3), .empty(4), .empty(5), .empty(6)],
            []
        ),
        Row(
            "four empty ones after a served one signal",
            [.empty(0), .empty(1), .empty(2), .served(3), .empty(4), .empty(5), .empty(6), .empty(7)],
            [7]
        ),
        Row("served connections alone never signal", [.served(0), .served(1), .served(2), .served(3), .served(4)], []),
        Row(
            "more empty ones straight after a signal do not signal again",
            [.empty(0), .empty(1), .empty(2), .empty(3), .empty(4), .empty(60)],
            [3]
        ),
        Row(
            "an empty one just inside 10 minutes of the signal does not signal",
            [.empty(0), .empty(1), .empty(2), .empty(3), .empty(602.9)],
            [3]
        ),
        Row(
            "an empty one 10 minutes after the signal signals again",
            [.empty(0), .empty(1), .empty(2), .empty(3), .empty(603)],
            [3, 4]
        ),
        Row(
            "a new spiral within 10 minutes of the last signal waits for the clock",
            [.empty(0), .empty(1), .empty(2), .empty(3), .served(10), .empty(20), .empty(21), .empty(22), .empty(23), .empty(603)],
            [3, 9]
        ),
    ]

    @Test(arguments: rows)
    func `signals four empty connections in a row, at most once per 10 minutes`(row: Row<[Ending], [Int]>) {
        var detector = SpiralDetector()

        let signals = row.input.indices.filter { index in
            let ending = row.input[index]
            return detector.connectionEnded(served: ending.served, at: Moment.after(ending.at))
        }

        #expect(signals == row.expected)
    }

    /// Whether the heartbeat carries the flag at a moment after the endings.
    struct Flag: Sendable {
        var endings: [Ending]
        var at: TimeInterval
    }

    static let flagRows: [Row<Flag, Bool>] = [
        Row("no flag before any signal", Flag(endings: [.empty(0), .empty(1), .empty(2)], at: 3), false),
        Row("the flag is up once it has signalled", Flag(endings: [.empty(0), .empty(1), .empty(2), .empty(3)], at: 3), true),
        Row("the flag stays up while the agent stays silent", Flag(endings: [.empty(0), .empty(1), .empty(2), .empty(3)], at: 602.9), true),
        Row("the flag goes down 10 minutes after the signal", Flag(endings: [.empty(0), .empty(1), .empty(2), .empty(3)], at: 603), false),
        Row(
            "a served connection takes the flag down",
            Flag(endings: [.empty(0), .empty(1), .empty(2), .empty(3), .served(5)], at: 6),
            false
        ),
        Row(
            "a second signal puts the flag up again",
            Flag(endings: [.empty(0), .empty(1), .empty(2), .empty(3), .empty(603)], at: 700),
            true
        ),
    ]

    @Test(arguments: flagRows)
    func `raises the heartbeat flag from a signal until the agent is served or 10 minutes pass`(row: Row<Flag, Bool>) {
        var detector = SpiralDetector()
        for ending in row.input.endings {
            _ = detector.connectionEnded(served: ending.served, at: Moment.after(ending.at))
        }

        #expect(detector.isSignalling(at: Moment.after(row.input.at)) == row.expected)
    }

    @Test func `counts the empty connections in a row`() {
        var detector = SpiralDetector()
        for second in 0..<6 {
            _ = detector.connectionEnded(served: false, at: Moment.after(Double(second)))
        }

        #expect(detector.emptyInARow == 6)
    }
}
