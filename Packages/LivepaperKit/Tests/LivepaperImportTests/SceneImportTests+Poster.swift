import Foundation
import Testing
import LivepaperCore
import LivepaperImport
import LivepaperScene
import LivepaperTestSupport

// A scene's poster, drawn from the scene once it is prepared, and cut from the item's preview
// only when it cannot be drawn. A Workshop preview can be a few hundred pixels wide, and the
// poster is what the desktop holds when nothing is drawn.
extension SceneImportTests {
    @Test(.enabled(if: GPU.device != nil))
    func `a scene's poster is drawn from the scene, at its own size up to 3840 wide`() async throws {
        let item = try workshop.writeSceneItem("3000000001", entries: SyntheticScene.liveScene(width: 6000, height: 3375))

        let outcome = try await bench.importer(sceneDrawing: PaintedScene.self).run(try candidate(at: item))

        guard case .importedScene(let wallpaper, _, let poster) = outcome else {
            Issue.record("not imported as a scene: \(outcome)")
            return
        }
        #expect(poster == .drawn(width: 3840, height: 2160))
        let file = bench.location.url(for: wallpaper.poster)
        #expect(try picture(at: file).size == [3840, 2160])
        #expect(ScenePoster.isDrawn(file))
        #expect(isClose(try meanColour(at: file), to: PaintedScene.colour(at: ScenePoster.time)))
        #expect(bench.names(in: file.deletingLastPathComponent()) == ["poster.heic", "preview.jpg", "project.json", "scene.pkg"])
        #expect(bench.stagingResidue.isEmpty)
    }

    @Test(.enabled(if: GPU.device != nil))
    func `a scene that cannot be drawn yet has its poster cut from the preview`() async throws {
        let item = try workshop.writeSceneItem("3000000001", entries: SyntheticScene.liveScene())

        let outcome = try await bench.importer(sceneDrawing: UnpreparedScene.self).run(try candidate(at: item))

        guard case .importedScene(let wallpaper, _, let poster) = outcome else {
            Issue.record("not imported as a scene: \(outcome)")
            return
        }
        #expect(poster == .notDrawn(reason: "it has no programs"))
        let file = bench.location.url(for: wallpaper.poster)
        #expect(try picture(at: file).size == [48, 27], "the square preview cut to the scene's shape")
        #expect(!ScenePoster.isDrawn(file), "so the app draws it once it can")
    }

    @Test(.enabled(if: GPU.device != nil))
    func `a scene with no preview is imported all the same when it can be drawn`() async throws {
        let item = try workshop.writeSceneItem("3000000001", entries: SyntheticScene.liveScene(width: 1920, height: 1080), preview: nil)

        let outcome = try await bench.importer(sceneDrawing: PaintedScene.self).run(try candidate(at: item))

        guard case .importedScene(let wallpaper, _, let poster) = outcome else {
            Issue.record("not imported as a scene: \(outcome)")
            return
        }
        #expect(poster == .drawn(width: 1920, height: 1080))
        let kept = bench.location.url(for: wallpaper.poster).deletingLastPathComponent()
        #expect(bench.names(in: kept) == ["poster.heic", "project.json", "scene.pkg"])
    }

    @Test func `an importer with nothing to draw scenes with cuts the poster from the preview`() async throws {
        let item = try workshop.writeSceneItem("3000000001", entries: SyntheticScene.liveScene())

        let outcome = try await bench.importer().run(try candidate(at: item))

        guard case .importedScene(_, _, let poster) = outcome else {
            Issue.record("not imported as a scene: \(outcome)")
            return
        }
        #expect(poster == .notDrawn(reason: "nothing draws scenes here"))
    }
}
