import Testing
import LivepaperCore

/// What the inspector's details say about a wallpaper's optimised copy.
struct DetailsWordsTests {
    static func details(
        seconds: Double = 24, width: Int = 3840, height: Int = 2160, fps: Double = 30, codec: String = "hevc"
    ) -> WallpaperDetails {
        WallpaperDetails(duration: seconds, width: width, height: height, frameRate: fps, codec: codec, byteCount: 71_000_000)
    }

    @Test func `the resolution is width by height`() {
        #expect(Self.details(width: 3840, height: 2160).resolutionWords == "3840 × 2160")
        #expect(Self.details(width: 1080, height: 1920).resolutionWords == "1080 × 1920")
    }

    static let lengths: [Row<Double, String>] = [
        Row("seconds, as minutes and seconds", 24, "0:24"),
        Row("to the nearest second", 12.5, "0:13"),
        Row("and down", 9.4, "0:09"),
        Row("minutes", 125, "2:05"),
        Row("an hour or more", 3723, "1:02:03"),
        Row("under half a second is still a second", 0.4, "0:01"),
        Row("no length at all", 0, "0:00"),
    ]

    @Test(arguments: lengths)
    func `the length is minutes and seconds`(row: Row<Double, String>) {
        #expect(Self.details(seconds: row.input).lengthWords == row.expected)
    }

    static let frameRates: [Row<Double, String>] = [
        Row("a whole rate", 30, "30 fps"),
        Row("sixty", 60, "60 fps"),
        Row("NTSC's rate, as the importer keeps it", 29.97, "29.97 fps"),
        Row("film's", 23.98, "23.98 fps"),
        Row("no trailing zero", 59.9, "59.9 fps"),
    ]

    @Test(arguments: frameRates)
    func `the frame rate is frames per second`(row: Row<Double, String>) {
        #expect(Self.details(fps: row.input).frameRateWords == row.expected)
    }

    static let codecs: [Row<String, String>] = [
        Row("HEVC, as the importer names it", "hevc", "HEVC"),
        Row("H.264, as the importer names it", "h264", "H.264"),
        Row("HEVC by its four-character code", "hvc1", "HEVC"),
        Row("H.264 by its four-character code", "avc1", "H.264"),
        Row("ProRes by name", "prores", "ProRes"),
        Row("ProRes 422 by its code", "apcn", "ProRes"),
        Row("ProRes 4444 by its code", "ap4h", "ProRes"),
        Row("anything else as it is, in capitals", "av01", "AV01"),
    ]

    @Test(arguments: codecs)
    func `the codec is named as people know it`(row: Row<String, String>) {
        #expect(Self.details(codec: row.input).codecWords == row.expected)
    }

    // MARK: Which rows

    static let rows: [Row<WallpaperKind, [WallpaperDetail]>] = [
        Row("a video's, as they always were", .video, [.resolution, .length, .frameRate, .codec, .size, .imported]),
        Row("a scene's say what it is, and have no length or codec", .scene, [.kind, .resolution, .frameRate, .size, .imported]),
    ]

    @Test(arguments: rows)
    func `the details shown depend on the kind of wallpaper`(row: Row<WallpaperKind, [WallpaperDetail]>) {
        var wallpaper = Wallpaper.numbered(1)
        if row.input == .scene {
            wallpaper.scene = WallpaperScene(project: .known("wallpapers/\(wallpaper.id)/project.json"), width: 3840, height: 2160)
        }

        #expect(wallpaper.kind == row.input)
        #expect(wallpaper.detailsShown == row.expected)
    }

    @Test func `the kind is named in words`() {
        #expect(WallpaperKind.video.words == "Video")
        #expect(WallpaperKind.scene.words == "Wallpaper Engine scene")
    }
}
