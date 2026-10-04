import Foundation
import Testing
@testable import LivepaperPlayback

/// Scene time runs only while a scene is drawn, and a scene resumes where it stopped.
struct SceneClockTests {
    enum Step: Sendable {
        case start
        case frame(at: Double)
        case stop
        case reset
    }

    static let rows: [Row<[Step], [Double]>] = [
        Row("the first frame is the scene's first moment", [.start, .frame(at: 100)], [0]),
        Row("frames are timed by when they are shown", [.start, .frame(at: 100), .frame(at: 100.5), .frame(at: 102)], [0, 0.5, 2]),
        Row(
            "a pause stops the time, and the next run carries on from it",
            [.start, .frame(at: 100), .frame(at: 101), .stop, .start, .frame(at: 500), .frame(at: 500.25)],
            [0, 1, 1, 1.25]
        ),
        Row(
            "a frame while stopped shows the time it stopped at",
            [.start, .frame(at: 10), .frame(at: 12), .stop, .frame(at: 90)],
            [0, 2, 2]
        ),
        Row("it never runs backwards", [.start, .frame(at: 10), .frame(at: 11), .frame(at: 10.5)], [0, 1, 1]),
        Row("a reset starts the scene again", [.start, .frame(at: 10), .frame(at: 13), .stop, .reset, .start, .frame(at: 40)], [0, 3, 0]),
    ]

    @Test(arguments: rows)
    func `scene time`(row: Row<[Step], [Double]>) {
        var clock = SceneClock()
        var times: [Double] = []
        for step in row.input {
            switch step {
            case .start: clock.start()
            case .frame(let moment): times.append(clock.time(forFrameAt: moment))
            case .stop: clock.stop()
            case .reset: clock.reset()
            }
        }

        #expect(times == row.expected)
    }

    @Test func `a scene's pictures are the ones its GPU finished, as a video's are its renderer's, whatever the window server presented`() {
        let before = SceneTally(asked: 10, committed: 10, completed: 9, presented: 9)
        let after = SceneTally(asked: 70, committed: 70, completed: 69, presented: 12)

        let count = SceneTally.count(from: before, to: after, over: .seconds(2), framesPerSecond: 30, engineReady: true)

        // Under the user's windows the window server presented 3 of 60: that is logged, not judged.
        #expect(count == PictureCount(displayed: 60, expected: 60, fed: 60, asked: 60, presented: 3))
    }

    @Test func `frames the GPU failed are neither shown nor fed, so failing is a stall`() {
        let before = SceneTally(asked: 0, committed: 0, completed: 0, failed: 0, presented: 0)
        let after = SceneTally(asked: 60, committed: 60, completed: 10, failed: 50, presented: 10)

        let count = SceneTally.count(from: before, to: after, over: .seconds(2), framesPerSecond: 30, engineReady: true)

        #expect(count == PictureCount(displayed: 10, expected: 60, fed: 10, asked: 60, presented: 10))
    }

    static let silentLink: [Row<Bool, PictureCount>] = [
        Row(
            "a link that is not called while the engine stands ready: the system withholds the frames",
            true, PictureCount(displayed: 0, expected: 60, fed: 0, asked: 0, withheld: true, presented: 0)
        ),
        Row(
            "a link that is not called while the engine does not answer: a stall",
            false, PictureCount(displayed: 0, expected: 60, fed: 0, asked: 0, withheld: false, presented: 0)
        ),
    ]

    @Test(arguments: silentLink)
    func `a silent display link is withheld only while the engine stands ready`(row: Row<Bool, PictureCount>) {
        let tally = SceneTally(asked: 40, committed: 40, completed: 40, presented: 40)

        let count = SceneTally.count(from: tally, to: tally, over: .seconds(2), framesPerSecond: 30, engineReady: row.input)

        #expect(count == row.expected)
    }

    @Test func `the engine stands ready while its frames are on the GPU no more than its latency allows`() {
        #expect(SceneTally(asked: 50, committed: 50, completed: 48).isGPUKeepingUp)
        #expect(!SceneTally(asked: 50, committed: 50, completed: 40).isGPUKeepingUp)
    }
}
