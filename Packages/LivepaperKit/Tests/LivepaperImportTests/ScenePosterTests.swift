import Foundation
import Synchronization
import Testing
import LivepaperCore
import LivepaperImport
import LivepaperScene
import LivepaperTestSupport

/// A scene's poster drawn from the scene itself, sharp at the scene's own size, instead of cut
/// from the Workshop item's preview, which can be a few hundred pixels wide.
struct ScenePosterTests {
    let folder: TemporaryFolder

    init() throws {
        folder = try TemporaryFolder()
    }

    static let sizes: [Row<[Double], [Int]>] = [
        Row("a 4K scene at its own size", [3840, 2160], [3840, 2160]),
        Row("a smaller one at its own size, never enlarged", [1920, 1080], [1920, 1080]),
        Row("a larger one with its longest side at 3840", [6000, 3375], [3840, 2160]),
        Row("an upright one the same way", [2160, 7680], [1080, 3840]),
        Row("an odd one to the nearest pixel", [5000, 3001], [3840, 2305]),
    ]

    @Test(arguments: sizes)
    func `the size a poster is drawn at`(row: Row<[Double], [Int]>) {
        let size = ScenePoster.pixels(for: Size(width: row.input[0], height: row.input[1]))

        #expect([size.width, size.height] == row.expected)
    }

    @Test(.enabled(if: GPU.device != nil))
    func `a poster is drawn from the scene, ten seconds in, after a second of pictures`() async throws {
        let scene = folder.folder("scene")
        let poster = scene.appending(path: SceneFolder.poster)
        try writePoster(to: poster, software: nil)

        let outcome = try await ScenePoster.draw(scene, size: Size(width: 64, height: 36), with: PaintedScene.self, to: poster)

        #expect(outcome == .drawn(width: 64, height: 36))
        let calls = PaintedScene.calls(for: scene)
        #expect(calls.sizes == [[64, 36]])
        // Thirty frames at the scene's rate lead up to it, so that effects carried from frame to frame have a picture.
        #expect(calls.times.count == 31)
        #expect(abs((calls.times.first ?? 0) - 9) < 0.000_001)
        #expect(calls.times.last == ScenePoster.time)
        let colour = try meanColour(at: poster)
        #expect(isClose(colour, to: PaintedScene.colour(at: 10)), "the picture at 10 s, not \(colour)")
        #expect(try picture(at: poster).size == [64, 36])
        #expect(ScenePoster.isDrawn(poster))
    }

    @Test(.enabled(if: GPU.device != nil))
    func `a scene that cannot be drawn leaves its poster as it was`() async throws {
        let scene = folder.folder("scene")
        let poster = scene.appending(path: SceneFolder.poster)
        try writePoster(to: poster, software: nil)
        let before = try Data(contentsOf: poster)

        let outcome = try await ScenePoster.draw(scene, size: Size(width: 64, height: 36), with: UnpreparedScene.self, to: poster)

        #expect(outcome == .notDrawn(reason: "it has no programs"))
        #expect(try Data(contentsOf: poster) == before)
        #expect(!ScenePoster.isDrawn(poster))
    }

    static let marks: [Row<String?, Bool>] = [
        Row("a poster drawn from its scene by this build", ScenePoster.marker, true),
        Row("a poster cut from the item's preview, which says nothing", nil, false),
        Row("a poster drawn by an earlier build", "Livepaper scene poster 0", false),
        Row("a poster drawn from programs an earlier translator made", "Livepaper scene poster 1, translator 0", false),
        Row("a picture another program wrote", "Photos", false),
    ]

    /// Programs translated anew are drawn with, so a poster drawn from the old ones is drawn again.
    @Test func `a drawn poster names the translator whose programs drew it`() {
        #expect(ScenePoster.marker == "Livepaper scene poster 1, translator \(ScenePrograms.currentTranslator)")
    }

    @Test(arguments: marks)
    func `a poster says whether it was drawn from its scene`(row: Row<String?, Bool>) throws {
        let poster = folder.file("poster.heic")
        try writePoster(to: poster, software: row.input)

        #expect(ScenePoster.isDrawn(poster) == row.expected)
    }

    @Test func `no poster at all was not drawn`() {
        #expect(!ScenePoster.isDrawn(folder.file("poster.heic")))
    }
}

/// Scenes already in the library, their posters drawn again at launch once they can be:
/// cut from the preview at an import that could not draw the scene, or by an earlier build.
struct ScenePosterRefreshTests {
    let bench: ImportBench

    init() throws {
        bench = try ImportBench()
    }

    enum Poster: Sendable {
        case none
        case fromPreview
        case drawn
    }

    /// A scene in the library with programs from `translator`, when set, and `poster`.
    func scene(_ number: Int, translator: Int?, poster: Poster) throws -> Wallpaper {
        let wallpaper = try bench.sceneWallpaper(number, entries: SyntheticScene.sceneWithEffect(), translator: translator)
        let file = bench.location.url(for: wallpaper.poster)
        switch poster {
        case .none: break
        case .fromPreview: try writePoster(to: file, software: nil)
        case .drawn: try writePoster(to: file, software: ScenePoster.marker)
        }
        return wallpaper
    }

    func posterBytes(of wallpapers: [Wallpaper]) throws -> [Data] {
        try wallpapers.map { try Data(contentsOf: bench.location.url(for: $0.poster)) }
    }

    static let current = ScenePrograms.currentTranslator
    static let old = ScenePrograms.currentTranslator - 1

    /// A scene's folder: the translator its programs are from, if it has any, and its poster.
    struct Folder: Sendable {
        var translator: Int?
        var poster: Poster
    }

    static let needs: [Row<Folder, Bool>] = [
        Row("a scene with its programs and the preview's poster", Folder(translator: current, poster: .fromPreview), true),
        Row("a scene with its programs and no poster", Folder(translator: current, poster: .none), true),
        Row("a scene whose poster was drawn from it already", Folder(translator: current, poster: .drawn), false),
        Row("a scene with no programs yet, which cannot be drawn", Folder(translator: nil, poster: .fromPreview), false),
        Row("a scene whose programs are another translator's, prepared first", Folder(translator: old, poster: .fromPreview), false),
    ]

    @Test(arguments: needs)
    func `which scenes have their poster drawn at launch`(row: Row<Folder, Bool>) throws {
        let wallpaper = try scene(1, translator: row.input.translator, poster: row.input.poster)

        #expect(ScenePoster.needsDrawing(wallpaper, in: bench.location) == row.expected)
    }

    @Test func `a video's poster is never drawn again`() throws {
        #expect(!ScenePoster.needsDrawing(try bench.video, in: bench.location))
    }

    @Test(.enabled(if: GPU.device != nil))
    func `posters are drawn one at a time, only those that need it, each written whole`() async throws {
        let preview = try scene(1, translator: Self.current, poster: .fromPreview)
        let drawn = try scene(2, translator: Self.current, poster: .drawn)
        let unprepared = try scene(3, translator: nil, poster: .fromPreview)
        let alsoPreview = try scene(4, translator: Self.current, poster: .fromPreview)
        let untouched = try posterBytes(of: [drawn, unprepared])
        let heard = Mutex<[WallpaperID]>([])

        let outcomes = await ScenePoster.refresh(
            [preview, try bench.video, drawn, unprepared, alsoPreview], in: bench.location, drawingType: PaintedScene.self
        ) { wallpaper, _ in
            heard.withLock { $0.append(wallpaper.id) }
        }

        let full = ScenePoster.Outcome.drawn(width: 1920, height: 1080)
        #expect(outcomes == [preview.id: full, alsoPreview.id: full])
        #expect(heard.withLock(\.self) == [preview.id, alsoPreview.id], "one at a time, in the library's order")
        for wallpaper in [preview, alsoPreview] {
            let poster = bench.location.url(for: wallpaper.poster)
            #expect(ScenePoster.isDrawn(poster))
            #expect(try picture(at: poster).size == [1920, 1080])
        }
        #expect(try posterBytes(of: [drawn, unprepared]) == untouched)
    }

    @Test(.enabled(if: GPU.device != nil))
    func `a scene that cannot be drawn keeps the preview's poster, and is tried again at the next launch`() async throws {
        let wallpaper = try scene(1, translator: Self.current, poster: .fromPreview)
        let before = try Data(contentsOf: bench.location.url(for: wallpaper.poster))

        let outcomes = await ScenePoster.refresh([wallpaper], in: bench.location, drawingType: UnpreparedScene.self) { _, _ in }

        let notDrawn = ScenePoster.Outcome.notDrawn(reason: "it has no programs")
        #expect(outcomes == [wallpaper.id: notDrawn])
        #expect(try posterBytes(of: [wallpaper]) == [before])
        #expect(ScenePoster.needsDrawing(wallpaper, in: bench.location))
    }
}
