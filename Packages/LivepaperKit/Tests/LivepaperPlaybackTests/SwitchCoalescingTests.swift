import Foundation
import Testing
@testable import LivepaperPlayback

private let videoA = URL(fileURLWithPath: "/Library/A/wallpaper.mov")
private let videoB = URL(fileURLWithPath: "/Library/B/wallpaper.mov")
private let videoC = URL(fileURLWithPath: "/Library/C/wallpaper.mov")

struct SwitchCoalescingTests {
    static let rows: [Row<[SwitchEvent], [SwitchAction]>] = [
        Row("the first request starts at once", [.request(videoA)], [.start(videoA)]),
        Row("a request for the video already playing is a no-op", [.request(videoA), .request(videoA)], [.start(videoA), .none]),
        Row("another video flushes the renderer first", [.request(videoA), .request(videoB)], [.start(videoA), .flush]),
        Row(
            "the end of the flush starts the video asked for",
            [.request(videoA), .request(videoB), .flushEnded],
            [.start(videoA), .flush, .start(videoB)]
        ),
        Row(
            "requests during a flush become one restart, on the last of them",
            [.request(videoA), .request(videoB), .request(videoC), .request(videoB), .request(videoC), .flushEnded],
            [.start(videoA), .flush, .none, .none, .none, .start(videoC)]
        ),
        Row(
            "the last request wins even when it is the video that was playing",
            [.request(videoA), .request(videoB), .request(videoA), .flushEnded],
            [.start(videoA), .flush, .none, .start(videoA)]
        ),
        Row(
            "a flush of the engine's own restarts what was playing",
            [.request(videoA), .flushBegan, .flushEnded],
            [.start(videoA), .flush, .start(videoA)]
        ),
        Row(
            "a flush of the engine's own while a switch is flushing is the same flush",
            [.request(videoA), .request(videoB), .flushBegan, .flushEnded],
            [.start(videoA), .flush, .none, .start(videoB)]
        ),
        Row(
            "a request during a flush of the engine's own is served when it ends",
            [.request(videoA), .flushBegan, .request(videoB), .flushEnded],
            [.start(videoA), .flush, .none, .start(videoB)]
        ),
        Row(
            "after the flush the video that started is the one playing",
            [.request(videoA), .request(videoB), .flushEnded, .request(videoB)],
            [.start(videoA), .flush, .start(videoB), .none]
        ),
        Row("nothing to restart before anything played", [.flushBegan], [.none]),
        Row("a flush that ends when none began does nothing", [.request(videoA), .flushEnded], [.start(videoA), .none]),
    ]

    @Test(arguments: rows)
    func `coalesces switches`(row: Row<[SwitchEvent], [SwitchAction]>) {
        var switches = SwitchCoalescer()

        let actions = row.input.map { switches.handle($0) }

        #expect(actions == row.expected)
    }

    @Test func `the video wanted after a flush is the last one requested`() {
        var switches = SwitchCoalescer()
        for event in [SwitchEvent.request(videoA), .request(videoB), .request(videoC)] { _ = switches.handle(event) }

        #expect(switches.playing == videoA)
        #expect(switches.isFlushing)
        #expect(switches.wanted == videoC)
    }

    @Test func `a switch while nothing may play is only remembered`() {
        var switches = SwitchCoalescer()
        _ = switches.handle(.request(videoA))

        switches.remember(videoB)

        #expect(switches.playing == videoB)
        #expect(switches.handle(.request(videoB)) == .none)
    }
}
