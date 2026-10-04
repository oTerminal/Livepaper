import AVFoundation
import CoreGraphics
import Foundation
import Testing
import LivepaperCore
import LivepaperImport
import LivepaperScene
import LivepaperTestSupport

/// A GIF scene becomes a video at import: its sprite sheet's
/// frames are an exact loop, so they need no renderer, and a video of them has
/// no seam.
struct GIFSceneImportTests {
    let bench: ImportBench
    let workshop: TemporaryFolder

    init() throws {
        bench = try ImportBench()
        workshop = try TemporaryFolder()
    }

    static let colours = [
        SyntheticScene.Colour(230, 30, 30), SyntheticScene.Colour(30, 230, 30), SyntheticScene.Colour(30, 30, 230),
        SyntheticScene.Colour(230, 230, 30), SyntheticScene.Colour(30, 230, 230), SyntheticScene.Colour(230, 30, 230),
    ]

    /// A GIF scene of 64 by 36 whose frames are `colours`, four to an image, so the sheet runs over two images.
    func writeGIFScene(frames texture: Data = Self.sixFrames) throws -> URL {
        let entries = SyntheticScene.gifScene(width: 64, height: 36, texture: texture)
        return try workshop.writeSceneItem("2900000001", entries: entries, sceneFile: "gifscene.json", title: "Botanical")
    }

    static let sixFrames = SyntheticScene.spriteSheet(colours, tile: (64, 36), perImage: 4, seconds: 0.1)

    func importGIFScene(_ item: URL) async throws -> (Wallpaper, ImportReport) {
        let candidate = try #require(discoverSources(at: item).candidates.first)
        let outcome = try await bench.importer().run(candidate)
        guard case .imported(let wallpaper, let report) = outcome else { throw Unexpected(outcome: outcome) }
        return (wallpaper, report)
    }

    struct Unexpected: Error {
        var outcome: ImportOutcome
    }

    /// The colour in the middle of the video's picture at `seconds`.
    func colour(of video: URL, at seconds: Double) async throws -> SyntheticScene.Colour {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 6000)).image
        var pixel = [UInt8](repeating: 0, count: 4)
        pixel.withUnsafeMutableBytes { buffer in
            let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
            context?.draw(image, in: CGRect(x: -image.width / 2, y: -image.height / 2, width: image.width, height: image.height))
        }
        return SyntheticScene.Colour(pixel[0], pixel[1], pixel[2])
    }

    static func near(_ one: SyntheticScene.Colour, _ other: SyntheticScene.Colour) -> Bool {
        [(one.red, other.red), (one.green, other.green), (one.blue, other.blue)].allSatisfy { abs(Int($0) - Int($1)) <= 24 }
    }

    @Test func `a GIF scene becomes a video of its frames, in order, that loops without a gap`() async throws {
        let item = try writeGIFScene()

        let (wallpaper, report) = try await importGIFScene(item)

        #expect(wallpaper.kind == .video)
        #expect(wallpaper.scene == nil)
        #expect(wallpaper.name == "Botanical")
        // The frames went in as ProRes and the optimised copy was written from them, once.
        #expect(report.plan == .transcode)
        #expect(report.writtenBy == .transcode)
        #expect(report.seam.passes)

        let optimisedCopy = bench.location.url(for: wallpaper.optimisedCopy)
        let seam = try await validateLoopSeam(of: optimisedCopy)
        #expect(seam.passes, "\(seam)")
        #expect(seam.frameCount == 6)
        #expect(wallpaper.details.width == 64 && wallpaper.details.height == 36)
        #expect(wallpaper.details.frameRate == 10)
        #expect(abs(wallpaper.details.duration - 0.6) < 0.001)
        for (index, expected) in Self.colours.enumerated() {
            let seen = try await colour(of: optimisedCopy, at: Double(index) * 0.1 + 0.05)
            #expect(Self.near(seen, expected), "frame \(index): \(seen), not \(expected)")
        }

        // An ordinary video wallpaper's folder: the frames' own file never reaches it, nor does the package.
        #expect(bench.names(in: optimisedCopy.deletingLastPathComponent()) == ["hover.mov", "poster.heic", "wallpaper.mov"])
        #expect(try picture(at: bench.location.url(for: wallpaper.poster)).size == [64, 36])
        #expect(bench.stagingResidue.isEmpty)
    }

    @Test func `each frame is shown for its own time`() async throws {
        let image = SyntheticScene.RawImage(width: 192, height: 36, pixels: Data((0..<36).flatMap { _ in
            Self.colours.prefix(3).flatMap { colour in (0..<64).flatMap { _ in [colour.red, colour.green, colour.blue, 255] } }
        }))
        let frames = [0.1, 0.2, 0.1].enumerated().map { index, seconds in
            SyntheticScene.Frame(image: 0, seconds: Float(seconds), x: Float(index * 64), y: 0, width: 64, height: 36)
        }
        let item = try writeGIFScene(frames: SyntheticScene.texture([image], frames: frames))

        let (wallpaper, _) = try await importGIFScene(item)

        let optimisedCopy = bench.location.url(for: wallpaper.optimisedCopy)
        #expect(try await validateLoopSeam(of: optimisedCopy).frameCount == 4)
        #expect(abs(wallpaper.details.duration - 0.4) < 0.001)
        for (seconds, expected) in [(0.05, 0), (0.15, 1), (0.25, 1), (0.35, 2)] {
            let seen = try await colour(of: optimisedCopy, at: seconds)
            #expect(Self.near(seen, Self.colours[expected]), "at \(seconds) s: \(seen), not \(Self.colours[expected])")
        }
    }

    @Test func `the same GIF scene again is a duplicate`() async throws {
        let item = try writeGIFScene()
        let (wallpaper, _) = try await importGIFScene(item)
        let candidate = try #require(discoverSources(at: item).candidates.first)

        #expect(try await bench.importer().run(candidate) == .duplicate(of: wallpaper))
    }

    @Test func `a sprite sheet that cannot be cut up is drawn live instead`() async throws {
        // One frame is no animation: the scene is kept to be drawn, as any other.
        let still = SyntheticScene.spriteSheet([Self.colours[0]], tile: (64, 36))
        let item = try writeGIFScene(frames: still)
        let candidate = try #require(discoverSources(at: item).candidates.first)

        let outcome = try await bench.importer().run(candidate)

        guard case .importedScene(let wallpaper, _, _) = outcome else {
            Issue.record("not kept as a scene: \(outcome)")
            return
        }
        #expect(wallpaper.scene?.width == 64 && wallpaper.scene?.height == 36)
    }

    static let rates: [Row<[Double], FrameRate>] = [
        Row("a tenth of a second", [0.1, 0.1], FrameRate(duration: 600, timescale: 6000)),
        Row("the shortest frame's, when they differ", [0.1, 0.05, 0.2], FrameRate(duration: 300, timescale: 6000)),
        Row("a frame time that is not a whole number of hundredths", [0.07], FrameRate(duration: 420, timescale: 6000)),
        Row("never faster than 60", [0.001, 0.1], FrameRate(duration: 100, timescale: 6000)),
    ]

    @Test(arguments: rates)
    func `the frames are written at their shortest time, on a clock that holds it exactly`(row: Row<[Double], FrameRate>) {
        #expect(spriteSheetRate(row.input) == row.expected)
    }
}
