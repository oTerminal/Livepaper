import AVFoundation
import CoreGraphics
import Foundation
import Synchronization
import Testing
import LivepaperCore
import LivepaperImport
import LivepaperScene
import LivepaperTestSupport

/// Wallpaper Engine scenes through the whole pipeline, on scene
/// items the tests make: a scene kept as its own files to be drawn live, and a
/// GIF scene that becomes a video.
struct SceneImportTests {
    let bench: ImportBench
    let workshop: TemporaryFolder

    init() throws {
        bench = try ImportBench()
        workshop = try TemporaryFolder()
    }

    func candidate(at item: URL) throws -> ImportCandidate {
        try #require(discoverSources(at: item).candidates.first)
    }

    // MARK: A scene drawn live

    @Test func `a scene is kept as its own files, to be drawn live`() async throws {
        let item = try workshop.writeSceneItem("3000000001", entries: SyntheticScene.liveScene(width: 3840, height: 2160))
        let package = try Data(contentsOf: item.appending(path: "scene.pkg"))

        let outcome = try await bench.importer().run(try candidate(at: item))

        guard case .importedScene(let wallpaper, _, _) = outcome else {
            Issue.record("not imported as a scene: \(outcome)")
            return
        }
        let folder = "wallpapers/\(wallpaper.id)"
        #expect(wallpaper.kind == .scene)
        #expect(wallpaper.name == "Lantern Street")
        #expect(wallpaper.scene == WallpaperScene(project: try LibraryPath("\(folder)/project.json"), width: 3840, height: 2160))
        #expect(wallpaper.optimisedCopy == (try LibraryPath("\(folder)/scene.pkg")))
        #expect(wallpaper.poster == (try LibraryPath("\(folder)/poster.heic")))
        #expect(wallpaper.hoverPreview == nil, "a still preview makes no hover preview")
        #expect(wallpaper.details.width == 3840 && wallpaper.details.height == 2160)
        #expect(wallpaper.details.duration == 0 && wallpaper.details.frameRate == 30 && wallpaper.details.codec == "scene")
        #expect(wallpaper.details.byteCount > package.count)
        #expect(wallpaper.volume == 0 && wallpaper.importedAt == ImportBench.importedAt)

        // The item's files, not its shader cache; the package byte for byte.
        let kept = bench.location.url(for: wallpaper.optimisedCopy).deletingLastPathComponent()
        #expect(bench.names(in: kept) == ["poster.heic", "preview.jpg", "project.json", "scene.pkg"])
        #expect(try Data(contentsOf: bench.location.url(for: wallpaper.optimisedCopy)) == package)
        #expect(try Data(contentsOf: kept.appending(path: "project.json")) == Data(contentsOf: item.appending(path: "project.json")))

        // The poster is the square preview cut to the scene's shape.
        let poster = try picture(at: bench.location.url(for: wallpaper.poster))
        #expect(poster.size == [48, 27])

        #expect(try bench.savedLibrary()[wallpaper.id] == wallpaper)
        #expect(bench.stagingResidue.isEmpty)
        #expect(bench.names(in: item) == ["preview.jpg", "project.json", "scene.pkg", "shaders"], "the item is only read")
    }

    @Test func `a scene goes through the scene's stages`() async throws {
        let item = try workshop.writeSceneItem("3000000001", entries: SyntheticScene.liveScene())
        let stages = Mutex<[ImportStage]>([])

        _ = try await bench.importer().run(try candidate(at: item)) { progress in
            stages.withLock { if $0.last != progress.stage { $0.append(progress.stage) } }
        }

        #expect(stages.withLock(\.self) == [.fingerprint, .probe, .prepare, .artefacts, .commit])
    }

    @Test func `the prepare hook runs on the staged folder, with the item's files already there`() async throws {
        let item = try workshop.writeSceneItem("3000000001", entries: SyntheticScene.liveScene())
        let seen = Mutex<[(folder: String, names: [String])]>([])
        let importer = Importer(
            location: bench.location, library: bench.library, ffmpeg: nil, shaderTools: nil,
            prepareScene: { folder in
                let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()) ?? []
                seen.withLock { $0.append((folder.deletingLastPathComponent().lastPathComponent, names)) }
                try Data("prepared".utf8).write(to: folder.appending(path: "prepared.bin"))
                return .prepared(programs: 3, failures: 1)
            }
        )

        let outcome = try await importer.run(try candidate(at: item))

        guard case .importedScene(let wallpaper, let preparation, _) = outcome else {
            Issue.record("not imported as a scene: \(outcome)")
            return
        }
        #expect(seen.withLock { $0.map(\.folder) } == [".staging"])
        #expect(seen.withLock { $0.first?.names } == ["preview.jpg", "project.json", "scene.pkg"])
        #expect(preparation == .prepared(programs: 3, failures: 1), "the hook's outcome is the import's")
        // What the hook writes is committed with the scene.
        let kept = bench.location.url(for: wallpaper.optimisedCopy).deletingLastPathComponent()
        #expect(bench.names(in: kept).contains("prepared.bin"))
    }

    struct PrepareFailed: Error {}

    // MARK: Preparing a scene's shaders

    static let unprepared: [Row<String, String>] = [
        Row("with no shader tools", "none", "the shader tools are missing"),
        Row("with tools that cannot be started", "gone", "glslang could not be started"),
    ]

    @Test(arguments: unprepared)
    func `a scene that cannot be prepared is imported all the same, with its poster`(row: Row<String, String>) async throws {
        let item = try workshop.writeSceneItem("3000000001", entries: SyntheticScene.sceneWithEffect())
        let gone = ShaderTools(glslang: workshop.file("gone/glslang"), spirvCross: workshop.file("gone/spirv-cross"))

        let outcome = try await bench.importer(shaderTools: row.input == "gone" ? gone : nil).run(try candidate(at: item))

        guard case .importedScene(let wallpaper, .notPrepared(let reason), _) = outcome else {
            Issue.record("not imported as an unprepared scene: \(outcome)")
            return
        }
        #expect(reason.hasPrefix(row.expected))
        let kept = bench.location.url(for: wallpaper.optimisedCopy).deletingLastPathComponent()
        #expect(bench.names(in: kept) == ["poster.heic", "preview.jpg", "project.json", "scene.pkg"])
        #expect(try bench.savedLibrary()[wallpaper.id] == wallpaper)
        #expect(bench.stagingResidue.isEmpty)
    }

    @Test(.enabled(if: ShaderToolsHelper.shouldRun))
    func `a scene that is prepared keeps its programs in its folder`() async throws {
        let item = try workshop.writeSceneItem("3000000001", entries: SyntheticScene.sceneWithEffect())

        let outcome = try await bench.importer(shaderTools: try ShaderToolsHelper.required()).run(try candidate(at: item))

        guard case .importedScene(let wallpaper, let preparation, _) = outcome else {
            Issue.record("not imported as a scene: \(outcome)")
            return
        }
        #expect(preparation == .prepared(programs: 2, failures: 0))
        let kept = bench.location.url(for: wallpaper.optimisedCopy).deletingLastPathComponent()
        #expect(bench.names(in: kept) == ["poster.heic", "preview.jpg", "project.json", "scene-programs.json", "scene.pkg"])
        #expect(ScenePrograms.translator(in: kept) == ScenePrograms.currentTranslator)
        #expect(bench.stagingResidue.isEmpty)
    }

    @Test func `a prepare hook that throws leaves nothing behind`() async throws {
        let item = try workshop.writeSceneItem("3000000001", entries: SyntheticScene.liveScene())
        let importer = Importer(
            location: bench.location, library: bench.library, ffmpeg: nil, shaderTools: nil, prepareScene: { _ in throw PrepareFailed() }
        )

        await #expect(throws: PrepareFailed.self) { try await importer.run(try candidate(at: item)) }

        #expect(bench.stagingResidue.isEmpty)
        #expect(bench.wallpaperFolders.isEmpty)
        #expect(try bench.savedLibrary().wallpapers.isEmpty)
    }

    @Test func `the same scene again is a duplicate, found before anything is written`() async throws {
        let item = try workshop.writeSceneItem("3000000001", entries: SyntheticScene.liveScene())
        let first = try await bench.importer().run(try candidate(at: item))
        guard case .importedScene(let wallpaper, _, _) = first else {
            Issue.record("not imported as a scene: \(first)")
            return
        }

        let again = try await bench.importer().run(try candidate(at: item))

        #expect(again == .duplicate(of: wallpaper))
        #expect(bench.wallpaperFolders == [wallpaper.id.description])
    }

    static let refused: [Row<[SyntheticScene.Entry], ImportError>] = [
        Row(
            "a scene with no size of its own",
            [SyntheticScene.Entry("scene.json", json: #"{"general": {"orthogonalprojection": {"auto": true}}, "objects": []}"#)],
            .sceneWithoutSize
        ),
        Row("a scene its package does not hold", [SyntheticScene.Entry("other.json", json: "{}")], .scene(.missingEntry("scene.json"))),
        Row("a scene nobody could read", [SyntheticScene.Entry("scene.json", json: "{ not JSON")], .scene(.malformedScene)),
    ]

    @Test(arguments: refused)
    func `a scene that cannot be drawn is refused, and leaves nothing behind`(row: Row<[SyntheticScene.Entry], ImportError>) async throws {
        let item = try workshop.writeSceneItem("3000000001", entries: row.input)

        await #expect(throws: row.expected) { try await bench.importer().run(try candidate(at: item)) }

        #expect(bench.stagingResidue.isEmpty)
        #expect(bench.wallpaperFolders.isEmpty)
    }

    @Test func `a package that is not one is refused`() async throws {
        let item = try workshop.writeSceneItem("3000000001", entries: SyntheticScene.liveScene())
        try Data("not a package".utf8).write(to: item.appending(path: "scene.pkg"))

        await #expect(throws: ImportError.scene(.notAPackage)) { try await bench.importer().run(try candidate(at: item)) }
    }

    @Test func `a scene with no preview has nothing to make a poster from`() async throws {
        let item = try workshop.writeSceneItem("3000000001", entries: SyntheticScene.liveScene(), preview: nil)

        await #expect(throws: ArtefactError.noPicture) { try await bench.importer().run(try candidate(at: item)) }

        #expect(bench.stagingResidue.isEmpty)
        #expect(bench.wallpaperFolders.isEmpty)
    }

    @Test(.enabled(if: Helper.shouldRun))
    func `an animated preview becomes the scene's hover preview, converted as any GIF is`() async throws {
        let colours = [SyntheticScene.Colour(220, 40, 40), SyntheticScene.Colour(40, 220, 40), SyntheticScene.Colour(40, 40, 220)]
        let item = try workshop.writeSceneItem(
            "3000000001", entries: SyntheticScene.liveScene(width: 1920, height: 1080), preview: .animated(side: 64, colours: colours)
        )

        let outcome = try await bench.importer(ffmpeg: try Helper.required()).run(try candidate(at: item))

        guard case .importedScene(let wallpaper, _, _) = outcome else {
            Issue.record("not imported as a scene: \(outcome)")
            return
        }
        let hoverPreview = bench.location.url(for: try #require(wallpaper.hoverPreview))
        #expect(try await validateLoopSeam(of: hoverPreview).passes)
        #expect(try await probeSource(at: hoverPreview).audio == nil)
        let kept = hoverPreview.deletingLastPathComponent()
        #expect(bench.names(in: kept) == ["hover.mov", "poster.heic", "preview.gif", "project.json", "scene.pkg"])
        // The poster is the GIF's first picture, cut to 16:9.
        let poster = try picture(at: bench.location.url(for: wallpaper.poster))
        #expect(poster.size == [64, 36])
    }
}
