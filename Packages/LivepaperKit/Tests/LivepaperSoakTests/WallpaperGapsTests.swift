import Foundation
import LivepaperSoak
import Testing

/// The largest presented gap per wallpaper and whether it fell at a seam, and the
/// gaps over 1.5 frame durations split at-seam and mid-pass.
struct WallpaperGapsTests {
    static func line(
        _ surface: Int, _ wallpaper: Int, loops: Int, gap: Double?, atSeam: Double?, overAtSeams: Int = 0, overMidPass: Int = 0
    ) -> MetricsLine {
        MetricsLine(
            surface: Named.surface(surface), folder: Named.wallpaper(wallpaper), file: "wallpaper.mov",
            loops: loops, seamsWatched: loops - 1, largestPresentedGap: gap, largestPresentedGapAtSeam: atSeam,
            gapsOverLimitAtSeams: overAtSeams, gapsOverLimitElsewhere: overMidPass
        )
    }

    @Test
    func `a wallpaper's largest gap, and whether it was at a seam`() {
        let gaps = WallpaperGaps([
            Self.line(1, 3, loops: 20, gap: 1.2, atSeam: 1.1),
            Self.line(1, 3, loops: 40, gap: 1.56, atSeam: 1.11, overMidPass: 1),
            Self.line(1, 4, loops: 20, gap: 1.8, atSeam: 1.8, overAtSeams: 1),
        ])

        #expect(gaps.wallpapers == [
            WallpaperGaps.Wallpaper(
                folder: Named.wallpaper(3), loops: 40, largest: 1.56, isLargestAtSeam: false, overLimitAtSeams: 0, overLimitMidPass: 1
            ),
            WallpaperGaps.Wallpaper(
                folder: Named.wallpaper(4), loops: 20, largest: 1.8, isLargestAtSeam: true, overLimitAtSeams: 1, overLimitMidPass: 0
            ),
        ])
    }

    @Test
    func `each engine's numbers run from its start, so a new start adds to the last one's`() {
        let gaps = WallpaperGaps([
            Self.line(1, 3, loops: 20, gap: 1.6, atSeam: 1.1, overMidPass: 1),
            Self.line(1, 3, loops: 40, gap: 1.6, atSeam: 1.1, overMidPass: 2),
            // Rotated away and back: the engine started again.
            Self.line(1, 3, loops: 20, gap: 1.4, atSeam: 1.4, overMidPass: 0),
            // The same wallpaper on another surface, counted with it.
            Self.line(5, 3, loops: 20, gap: 1.7, atSeam: 1.2, overAtSeams: 0, overMidPass: 3),
        ])

        #expect(gaps.wallpapers.map(\.loops) == [80])
        #expect(gaps.wallpapers.map(\.overLimitMidPass) == [5])
        #expect(gaps.wallpapers.map(\.largest) == [1.7])
    }

    @Test
    func `a wallpaper the probe never saw a picture of has no gap`() {
        let gaps = WallpaperGaps([Self.line(1, 3, loops: 20, gap: nil, atSeam: nil)])

        #expect(gaps.wallpapers.map(\.largest) == [nil])
        #expect(gaps.wallpapers.map(\.isLargestAtSeam) == [false])
    }
}
