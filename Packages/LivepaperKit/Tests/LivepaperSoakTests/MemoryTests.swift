import Foundation
import LivepaperSoak
import Testing

/// The last quarter hour's mean RSS at most 10 % over the second's, app and
/// extension; the first is warm-up; under 100 samples, inconclusive
/// (for the two-hour soak).
struct MemoryTests {
    /// One sample a minute from the soak's start, `rss(window)` kilobytes in quarter hour `window` (1-based).
    static func samples(count: Int = 120, process: String = "WallpaperExtension", rss: (Int) -> Int) -> [ResourceSample] {
        (0..<count).map { index in
            let seconds = TimeInterval(index * 60 + 30)
            return ResourceSample(time: .soak(seconds), process: process, pid: 711, cpu: 1.5, rssKilobytes: rss(Int(seconds) / 900 + 1))
        }
    }

    static let rows: [Row<[ResourceSample], MemoryTrend.Verdict>] = [
        Row("flat", samples { _ in 100_000 }, .pass(growth: 0)),
        Row("the first quarter hour is warm-up", samples { $0 == 1 ? 20_000 : 100_000 }, .pass(growth: 0)),
        Row("9 % more by the last quarter hour", samples { $0 == 8 ? 109_000 : 100_000 }, .pass(growth: 0.09)),
        Row("11 % more by the last quarter hour", samples { $0 == 8 ? 111_000 : 100_000 }, .fail(growth: 0.11)),
        Row("under 100 samples", samples(count: 99) { _ in 100_000 }, .inconclusive("99 samples, under 100")),
        Row("stopped before the last quarter hour", samples(count: 104) { _ in 100_000 }, .inconclusive("no samples in minutes 105–120")),
    ]

    @Test(arguments: rows)
    func `the memory rule`(row: Row<[ResourceSample], MemoryTrend.Verdict>) throws {
        let trend = MemoryTrend(process: "WallpaperExtension", samples: row.input, start: .soakStart)

        switch (trend.verdict, row.expected) {
        case let (.pass(growth), .pass(expected)), let (.fail(growth), .fail(expected)):
            #expect(abs(growth - expected) < 0.000_1)
        default:
            #expect(trend.verdict == row.expected)
        }
    }

    @Test
    func `quarter-hour means, and only the process asked for`() {
        let samples = Self.samples(count: 45) { $0 * 1_000 } + Self.samples(count: 45, process: "Livepaper") { _ in 5 }
        let trend = MemoryTrend(process: "WallpaperExtension", samples: samples, start: .soakStart)

        #expect(trend.windowMeans == [1: 1_000, 2: 2_000, 3: 3_000])
        #expect(trend.sampleCount == 45)
    }

    @Test
    func `reads soak.sh's samples, counting a row it cannot read`() throws {
        let csv = """
        time,process,pid,cpu,rss_kb
        2026-09-28T10:00:00+0100,WallpaperExtension,711,2.5,104232
        2026-09-28T10:00:00+0100,Livepaper,500,0.0,88120
        2026-09-28T10:05:00+0100,WallpaperExtension,711,,104300

        """

        let read = ResourceSample.read(csv: csv)

        #expect(read.samples == [
            ResourceSample(
                time: Date(timeIntervalSince1970: 1_790_586_000), process: "WallpaperExtension", pid: 711, cpu: 2.5, rssKilobytes: 104_232
            ),
            ResourceSample(time: Date(timeIntervalSince1970: 1_790_586_000), process: "Livepaper", pid: 500, cpu: 0, rssKilobytes: 88_120),
        ])
        #expect(read.unreadRows == 1)
    }
}
