import Testing
import DesignSystem

/// Time is a plain offset from an arbitrary start, advanced by hand.
private typealias Dwell = HoverDwell<String, ContinuousClock.Instant>

private struct Timeline {
    let start = ContinuousClock.now
    func at(_ milliseconds: Int) -> ContinuousClock.Instant { start + .milliseconds(milliseconds) }
}

struct HoverDwellTests {
    private let time = Timeline()

    @Test func `nothing is live before the pointer arrives`() {
        #expect(Dwell().live == nil)
    }

    @Test func `a tile is still a poster just before 200 ms`() {
        var dwell = Dwell()
        dwell.send(.enter("a"), at: time.at(0))
        dwell.send(.tick, at: time.at(199))

        #expect(dwell.live == nil)
    }

    @Test func `a tile goes live after a 200 ms dwell`() {
        var dwell = Dwell()
        dwell.send(.enter("a"), at: time.at(0))
        dwell.send(.tick, at: time.at(200))

        #expect(dwell.live == "a")
    }

    @Test func `leaving before the dwell ends keeps the poster`() {
        var dwell = Dwell()
        dwell.send(.enter("a"), at: time.at(0))
        dwell.send(.exit("a"), at: time.at(150))
        dwell.send(.tick, at: time.at(400))

        #expect(dwell.live == nil)
    }

    @Test func `leaving a live tile returns it to its poster`() {
        var dwell = Dwell()
        dwell.send(.enter("a"), at: time.at(0))
        dwell.send(.tick, at: time.at(200))
        dwell.send(.exit("a"), at: time.at(900))

        #expect(dwell.live == nil)
    }

    @Test func `coming back restarts the dwell`() {
        var dwell = Dwell()
        dwell.send(.enter("a"), at: time.at(0))
        dwell.send(.exit("a"), at: time.at(150))
        dwell.send(.enter("a"), at: time.at(160))
        dwell.send(.tick, at: time.at(300))

        #expect(dwell.live == nil)
    }

    @Test func `moving to another tile hands the live preview over after its own dwell`() {
        var dwell = Dwell()
        dwell.send(.enter("a"), at: time.at(0))
        dwell.send(.tick, at: time.at(200))
        // The next tile's enter can arrive before the first tile's exit.
        dwell.send(.enter("b"), at: time.at(500))
        dwell.send(.tick, at: time.at(600))
        #expect(dwell.live == "a")

        dwell.send(.tick, at: time.at(700))
        #expect(dwell.live == "b")
    }

    @Test func `a late exit from the previous tile does not stop the new one`() {
        var dwell = Dwell()
        dwell.send(.enter("a"), at: time.at(0))
        dwell.send(.enter("b"), at: time.at(50))
        dwell.send(.exit("a"), at: time.at(60))
        dwell.send(.tick, at: time.at(250))

        #expect(dwell.live == "b")
    }

    @Test func `the next deadline is 200 ms after the pointer arrived`() {
        var dwell = Dwell()
        #expect(dwell.deadline == nil)

        dwell.send(.enter("a"), at: time.at(40))
        #expect(dwell.deadline == time.at(240))

        dwell.send(.tick, at: time.at(240))
        #expect(dwell.deadline == nil)
    }

    @Test func `with hover autoplay off nothing goes live`() {
        var dwell = Dwell(isEnabled: false)
        dwell.send(.enter("a"), at: time.at(0))
        dwell.send(.tick, at: time.at(500))

        #expect(dwell.live == nil)
    }

    @Test func `switching hover autoplay off stops the live preview`() {
        var dwell = Dwell()
        dwell.send(.enter("a"), at: time.at(0))
        dwell.send(.tick, at: time.at(200))
        dwell.isEnabled = false

        #expect(dwell.live == nil)
    }
}
