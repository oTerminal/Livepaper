import Foundation
import Testing
import LivepaperImport

struct FrameScheduleTests {
    struct Source: Sendable {
        /// Seconds.
        var pts: [Double]
        var end: Double
        var rate: FrameRate = FrameRate(duration: 1, timescale: 30)
    }

    // Worked by hand: slot k is at k/30 s and shows the last frame that starts before its middle.
    static let schedules: [Row<Source, [Int]>] = [
        Row("a constant rate is left alone: every frame once", Source(pts: [0, 1.0 / 30, 2.0 / 30], end: 3.0 / 30), [1, 1, 1]),
        Row("a tick of jitter changes nothing", Source(pts: [0, 0.0334, 0.0666], end: 0.1001), [1, 1, 1]),
        Row("a gap in a variable rate holds the frame before it", Source(pts: [0, 1.0 / 30, 3.0 / 30], end: 4.0 / 30), [1, 2, 1]),
        Row("a first frame off zero is moved to zero", Source(pts: [2.0 / 30, 3.0 / 30, 4.0 / 30], end: 5.0 / 30), [1, 1, 1]),
        Row("twice the rate: every other frame is left out", Source(pts: [0, 1.0 / 60, 2.0 / 60, 3.0 / 60], end: 4.0 / 60), [1, 0, 1, 0]),
        Row("a long last frame is held to its end", Source(pts: [0, 1.0 / 30], end: 5.0 / 30), [1, 4]),
        Row("something is always shown, however short", Source(pts: [0], end: 0.001), [1]),
        Row(
            "a GIF's hundredths at 10 fps",
            Source(pts: [0, 0.1, 0.2], end: 0.3, rate: FrameRate(duration: 1, timescale: 10)),
            [1, 1, 1]
        ),
    ]

    @Test(arguments: schedules)
    func `says how many frames of the constant rate each source frame fills`(row: Row<Source, [Int]>) {
        var resampler = ConstantRateResampler(rate: row.input.rate)
        var counts: [Int] = []
        for pts in row.input.pts {
            if let count = resampler.next(pts: pts) { counts.append(count) }
        }
        counts.append(resampler.finish(end: row.input.end))

        #expect(counts == row.expected)
        #expect(resampler.framesWritten == row.expected.reduce(0, +))
    }

    static let rates: [Row<VideoProbe, FrameRate>] = [
        Row("a constant rate is kept to the tick", .clean(), FrameRate(duration: 512, timescale: 15360)),
        Row(
            "NTSC stays NTSC",
            .clean { $0.timing = .constant(FrameRate(duration: 1001, timescale: 30000)) },
            FrameRate(duration: 1001, timescale: 30000)
        ),
        Row(
            "a variable rate becomes the rate of its shortest frame, so no frame is lost",
            .clean { $0.timing = .variable; $0.nominalFrameRate = 25; $0.minFrameDuration = 1.0 / 30 },
            FrameRate(duration: 100, timescale: 3000)
        ),
        Row(
            "a shortest frame near NTSC is NTSC",
            .clean { $0.timing = .variable; $0.minFrameDuration = 0.03337 },
            FrameRate(duration: 1001, timescale: 30000)
        ),
        Row(
            "a screen recording with one very short frame stops at 60",
            .clean { $0.timing = .variable; $0.minFrameDuration = 0.001 },
            FrameRate(duration: 100, timescale: 6000)
        ),
        Row(
            "no shortest frame on record: the nominal rate",
            .clean { $0.timing = .variable; $0.minFrameDuration = 0; $0.nominalFrameRate = 24.2 },
            FrameRate(duration: 100, timescale: 2400)
        ),
        Row(
            "nothing on record at all: 30",
            .clean { $0.timing = .variable; $0.minFrameDuration = 0; $0.nominalFrameRate = 0 },
            FrameRate(duration: 100, timescale: 3000)
        ),
    ]

    @Test(arguments: rates)
    func `picks the optimised copy's frame rate`(row: Row<VideoProbe, FrameRate>) {
        #expect(FrameRate.forOptimisedCopy(of: row.input) == row.expected)
    }

    static let reductions: [Row<FrameRate, FrameRate>] = [
        Row("60 becomes 15", FrameRate(duration: 100, timescale: 6000), FrameRate(duration: 400, timescale: 6000)),
        Row("30 becomes 15", FrameRate(duration: 512, timescale: 15360), FrameRate(duration: 1024, timescale: 15360)),
        Row("NTSC becomes half NTSC", FrameRate(duration: 1001, timescale: 30000), FrameRate(duration: 2002, timescale: 30000)),
        Row("24 becomes 12", FrameRate(duration: 100, timescale: 2400), FrameRate(duration: 200, timescale: 2400)),
        Row("10 stays", FrameRate(duration: 1, timescale: 10), FrameRate(duration: 1, timescale: 10)),
    ]

    @Test(arguments: reductions)
    func `a hover preview takes every nth frame, so that it stays as long as the wallpaper`(row: Row<FrameRate, FrameRate>) {
        #expect(row.input.reduced(toAtMost: 15) == row.expected)
    }
}
