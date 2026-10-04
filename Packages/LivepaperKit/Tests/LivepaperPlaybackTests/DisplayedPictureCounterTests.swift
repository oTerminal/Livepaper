import LivepaperCore
import Testing
@testable import LivepaperPlayback

private typealias Sighting = DisplayedPictureCounterTests.Sighting

/// A 30 fps wallpaper whose picture changes every frame from `start`: `count` sightings, one per frame.
private func steady(from start: Double, count: Int, firstPicture: PictureID = 1) -> [Sighting] {
    (0 ..< count).map { Sighting(firstPicture + PictureID($0), start + Double($0) / 30) }
}

struct DisplayedPictureCounterTests {
    /// One poll of the picture on screen: the ID of the `IOSurface` behind it, nil when there was none,
    /// at a host time in seconds, and the frames the engine had fed the renderer by then.
    struct Sighting: Sendable {
        var picture: PictureID?
        var at: Double
        var fed: Int

        init(_ picture: PictureID?, _ at: Double, fed: Int = 0) {
            self.picture = picture
            self.at = at
            self.fed = fed
        }
    }

    static let rows: [Row<[Sighting], Int>] = [
        Row("the same picture polled again does not count", [Sighting(1, 10.1), Sighting(1, 10.2), Sighting(1, 10.6)], 0),
        Row("each change of picture counts", [Sighting(1, 10.1), Sighting(2, 10.2), Sighting(3, 10.3)], 2),
        Row("the first picture seen was already there", [Sighting(5, 10.1)], 0),
        Row("a picture that comes back counts again", [Sighting(1, 10.1), Sighting(2, 10.2), Sighting(1, 10.3)], 2),
        Row("no picture for a poll is not a change", [Sighting(1, 10.1), Sighting(nil, 10.2), Sighting(1, 10.3)], 0),
        Row("a new picture after none counts once", [Sighting(1, 10.1), Sighting(nil, 10.2), Sighting(2, 10.3)], 1),
        Row(
            "polls before the window opens do not count",
            [Sighting(1, 9.8), Sighting(2, 9.9), Sighting(3, 10.1), Sighting(4, 10.2)],
            1
        ),
        Row(
            "polls once the window has closed do not count",
            [Sighting(1, 10.1), Sighting(2, 11.9), Sighting(3, 12.0), Sighting(4, 12.1)],
            1
        ),
        Row("a covered surface shows nothing new", Array(repeating: Sighting(7, 11), count: 500), 0),
        Row("a playing surface shows every frame", steady(from: 10, count: 60), 59),
    ]

    @Test(arguments: rows)
    func `counts the pictures that changed in the window`(row: Row<[Sighting], Int>) {
        var counter = DisplayedPictureCounter(from: 10, window: .seconds(2), frameDuration: 1.0 / 30)

        for sighting in row.input { counter.observe(sighting.picture, fed: sighting.fed, at: sighting.at) }

        #expect(counter.count.displayed == row.expected)
    }

    static let feeding: [Row<[Sighting], Int>] = [
        Row(
            "frames fed between the window's first and last polls count",
            [Sighting(1, 10.1, fed: 100), Sighting(1, 10.5, fed: 112), Sighting(1, 11.9, fed: 157)],
            57
        ),
        Row(
            "frames fed before the window opens do not count",
            [Sighting(1, 9.9, fed: 90), Sighting(1, 10.1, fed: 100), Sighting(1, 11.9, fed: 157)],
            57
        ),
        Row(
            "frames fed once the window has closed do not count",
            [Sighting(1, 10.1, fed: 100), Sighting(1, 11.9, fed: 157), Sighting(1, 12.0, fed: 160)],
            57
        ),
        Row("a poll with no picture still reads what was fed", [Sighting(nil, 10.1, fed: 100), Sighting(nil, 11.9, fed: 157)], 57),
        Row("one poll sees nothing fed", [Sighting(1, 10.1, fed: 100)], 0),
        Row("no poll in the window sees nothing fed", [Sighting(1, 9.9, fed: 90), Sighting(1, 12.0, fed: 160)], 0),
    ]

    @Test(arguments: feeding)
    func `counts the frames fed over the same polls`(row: Row<[Sighting], Int>) {
        var counter = DisplayedPictureCounter(from: 10, window: .seconds(2), frameDuration: 1.0 / 30)

        for sighting in row.input { counter.observe(sighting.picture, fed: sighting.fed, at: sighting.at) }

        #expect(counter.count.fed == row.expected)
    }

    static let expectations: [Row<Double, Int>] = [
        Row("30 fps for 2 s", 1.0 / 30, 60),
        Row("60 fps for 2 s", 1.0 / 60, 120),
        Row("24 fps for 2 s", 1.0 / 24, 48),
        Row("an unknown frame rate expects nothing", 0, 0),
    ]

    @Test(arguments: expectations)
    func `expects one picture per frame of the window`(row: Row<Double, Int>) {
        let counter = DisplayedPictureCounter(from: 10, window: .seconds(2), frameDuration: row.input)

        #expect(counter.count.expected == row.expected)
    }

    @Test func `the window is over at its end`() {
        let counter = DisplayedPictureCounter(from: 10, window: .milliseconds(1500), frameDuration: 1.0 / 30)

        #expect(!counter.isOver(at: 11.4))
        #expect(counter.isOver(at: 11.5))
    }

    static let verdicts: [Row<[Sighting], WatchdogVerdict>] = [
        Row("every frame shown is healthy", steady(from: 10, count: 61), .healthy),
        Row("half the frames shown is healthy", steady(from: 10, count: 31), .healthy),
        Row("a third of the frames shown is a stall", steady(from: 10, count: 21), .flush),
        Row("nothing new is a stall", [Sighting(3, 10.5), Sighting(3, 11.5)], .flush),
    ]

    @Test(arguments: verdicts)
    func `the count is what the watchdog judges`(row: Row<[Sighting], WatchdogVerdict>) {
        var counter = DisplayedPictureCounter(from: 10, window: .seconds(2), frameDuration: 1.0 / 30)
        for sighting in row.input { counter.observe(sighting.picture, fed: sighting.fed, at: sighting.at) }

        let count = counter.count
        let verdict = judgeProgress(before: 0, after: count.displayed, expected: count.expected, attempt: 0)

        #expect(verdict == row.expected)
    }

    @Test func `a covered surface the engine feeds as usual is not composited`() {
        var counter = DisplayedPictureCounter(from: 10, window: .seconds(2), frameDuration: 1.0 / 30)
        var schedule = WatchdogSchedule()

        // The picture stops changing under a fullscreen app while the engine keeps enqueueing.
        for frame in 0 ..< 60 { counter.observe(7, fed: 200 + frame, at: 10 + Double(frame) / 30) }

        #expect(counter.count == PictureCount(displayed: 0, expected: 60, fed: 59))
        #expect(schedule.judge(.numbered(1), counter.count) == .notComposited)
    }
}

struct PresentedGapsTests {
    private static let frame = 1.0 / 30

    @Test func `a picture a frame is no gap`() {
        var gaps = PresentedGaps(frameDuration: Self.frame)

        for sighting in steady(from: 10, count: 90) { gaps.observe(sighting.picture, at: sighting.at) }

        #expect(gaps.intervals == 89)
        #expect(gaps.overLimitAtSeams == 0)
        #expect(gaps.overLimitElsewhere == 0)
        #expect(abs((gaps.largest ?? 0) - 1) < 0.001)
    }

    @Test func `a picture held for two frames inside a pass is a gap elsewhere`() {
        var gaps = PresentedGaps(frameDuration: Self.frame)
        var sightings = steady(from: 10, count: 30)
        sightings.remove(at: 15)

        for sighting in sightings { gaps.observe(sighting.picture, at: sighting.at) }

        #expect(gaps.overLimitElsewhere == 1)
        #expect(gaps.overLimitAtSeams == 0)
        #expect(abs((gaps.largest ?? 0) - 2) < 0.001)
    }

    @Test func `a picture held for two frames across a seam is a gap at the seam`() {
        var gaps = PresentedGaps(frameDuration: Self.frame)
        var sightings = steady(from: 10, count: 30)
        sightings.remove(at: 15)
        gaps.seam(dueAt: 10 + 15.0 / 30)

        for sighting in sightings { gaps.observe(sighting.picture, at: sighting.at) }

        #expect(gaps.overLimitAtSeams == 1)
        #expect(gaps.overLimitElsewhere == 0)
        #expect(gaps.seamsWatched == 1)
        #expect(abs((gaps.largestAtSeam ?? 0) - 2) < 0.001)
    }

    @Test func `a clean seam is watched and has no gap`() {
        var gaps = PresentedGaps(frameDuration: Self.frame)
        gaps.seam(dueAt: 10 + 15.0 / 30)

        for sighting in steady(from: 10, count: 30) { gaps.observe(sighting.picture, at: sighting.at) }

        #expect(gaps.seamsWatched == 1)
        #expect(gaps.overLimitAtSeams == 0)
        #expect(abs((gaps.largestAtSeam ?? 0) - 1) < 0.001)
    }

    @Test func `a seam while nobody was looking is not watched`() {
        var gaps = PresentedGaps(frameDuration: Self.frame)
        gaps.seam(dueAt: 5)

        for sighting in steady(from: 10, count: 30) { gaps.observe(sighting.picture, at: sighting.at) }

        #expect(gaps.seamsWatched == 0)
    }

    @Test func `a pause is not a gap`() {
        var gaps = PresentedGaps(frameDuration: Self.frame)
        for sighting in steady(from: 10, count: 10) { gaps.observe(sighting.picture, at: sighting.at) }

        gaps.interrupt(at: 10.4)
        for sighting in steady(from: 20, count: 30, firstPicture: 100) { gaps.observe(sighting.picture, at: sighting.at) }

        #expect(gaps.overLimitElsewhere == 0)
        #expect(abs((gaps.largest ?? 0) - 1) < 0.001)
    }

    @Test func `the first half second after an interruption is not measured`() {
        var gaps = PresentedGaps(frameDuration: Self.frame)
        gaps.interrupt(at: 10)

        // A decoder warming up: a picture held for three frames just after the start.
        let sightings = [Sighting(1, 10.0), Sighting(2, 10.1), Sighting(3, 10.2)] + steady(from: 11, count: 30, firstPicture: 10)
        for sighting in sightings { gaps.observe(sighting.picture, at: sighting.at) }

        #expect(gaps.overLimitElsewhere == 0)
        #expect(gaps.intervals == 29)
    }
}
