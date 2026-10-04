import Foundation
import Testing
import LivepaperCore
import LivepaperImport
import LivepaperScene
import LivepaperTestSupport

// What a scene's folder in the library is made of: files, never links, under names the library can hold.
extension SceneImportTests {
    @Test func `a package and a preview that are links inside the item are kept as the files they lead to`() async throws {
        let item = try workshop.writeSceneItem("3000000001", entries: SyntheticScene.liveScene())
        for name in ["scene.pkg", "preview.jpg"] {
            let data = item.appending(path: "data/\(name)")
            try FileManager.default.createDirectory(at: data.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: item.appending(path: name), to: data)
            try FileManager.default.createSymbolicLink(atPath: item.appending(path: name).path, withDestinationPath: "data/\(name)")
        }

        let outcome = try await bench.importer().run(try candidate(at: item))

        guard case .importedScene(let wallpaper, _, _) = outcome else {
            Issue.record("not imported as a scene: \(outcome)")
            return
        }
        let kept = bench.location.url(for: wallpaper.optimisedCopy).deletingLastPathComponent()
        for name in ["scene.pkg", "preview.jpg", "project.json"] {
            let file = kept.appending(path: name)
            let type = try FileManager.default.attributesOfItem(atPath: file.path)[.type] as? FileAttributeType
            #expect(type == .typeRegular, "\(name) is a \(String(describing: type))")
            #expect(try Data(contentsOf: file) == Data(contentsOf: item.appending(path: name)))
        }
    }

    @Test func `a package whose link leads out of the item by the time it is imported is refused, leaving nothing`() async throws {
        let item = try workshop.writeSceneItem("3000000001", entries: SyntheticScene.liveScene())
        let found = try candidate(at: item)
        // Changed after discovery looked: the link now leads to a package outside the item.
        let outside = workshop.file("elsewhere/scene.pkg")
        try FileManager.default.createDirectory(at: outside.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: item.appending(path: "scene.pkg"), to: outside)
        try FileManager.default.createSymbolicLink(at: item.appending(path: "scene.pkg"), withDestinationURL: outside)

        await #expect(throws: WallpaperEngineProjectError.escapesFolder("scene.pkg")) { try await bench.importer().run(found) }

        #expect(bench.stagingResidue.isEmpty)
        #expect(bench.wallpaperFolders.isEmpty)
    }

    @Test func `a scene whose file has a space in its name is kept under a name the library can hold, and reads`() async throws {
        let entries = SyntheticScene.liveScene(sceneFile: "night scene.json")
        let item = try workshop.writeSceneItem("3000000001", entries: entries, sceneFile: "night scene.json")

        let outcome = try await bench.importer().run(try candidate(at: item))

        guard case .importedScene(let wallpaper, _, _) = outcome else {
            Issue.record("not imported as a scene: \(outcome)")
            return
        }
        #expect(wallpaper.optimisedCopy == (try LibraryPath("wallpapers/\(wallpaper.id)/night_scene.pkg")))
        let original = try Data(contentsOf: item.appending(path: "night scene.pkg"))
        #expect(try Data(contentsOf: bench.location.url(for: wallpaper.optimisedCopy)) == original)
        // What the extension reads: the scene, from its folder in the library.
        let folder = bench.location.url(for: wallpaper.optimisedCopy).deletingLastPathComponent()
        #expect(try SceneDocument(folder: folder).files.sceneFile == "night scene.json")
    }
}
