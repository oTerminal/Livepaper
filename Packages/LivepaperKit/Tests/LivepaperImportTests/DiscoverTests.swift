import Foundation
import Testing
import LivepaperImport

struct DiscoverTests {
    let folder: TemporaryFolder

    init() throws {
        folder = try TemporaryFolder()
    }

    static let videoProject = #"{"file": "rain.webm", "preview": "preview.jpg", "title": "Rainy Night", "type": "video"}"#

    @Test func `a file is a candidate named after itself`() throws {
        let file = try folder.write(to: "Ocean at Dusk.mp4")

        let found = try discoverSources(at: file)

        #expect(found == Discovery(candidates: [ImportCandidate(source: file, name: "Ocean at Dusk")]))
    }

    @Test func `a file the user picked is a candidate whatever it is called, since the probe decides`() throws {
        let file = try folder.write(to: "clip.bin")

        #expect(try discoverSources(at: file).candidates.map(\.source) == [file])
    }

    @Test func `a folder gives its video files in name order, nested ones included`() throws {
        try folder.write(to: "b.mov")
        try folder.write(to: "a.MP4")
        try folder.write(to: "more/c.webm")
        try folder.write(to: "more/d.gif")
        try folder.write(to: "notes.txt")
        try folder.write(to: "cover.jpg")
        try folder.write(to: ".hidden.mp4")
        try folder.write(to: ".cache/e.mp4")

        let found = try discoverSources(at: folder.url)

        #expect(found.candidates.map(\.name) == ["a", "b", "c", "d"])
        #expect(found.skipped.isEmpty)
    }

    @Test func `a Wallpaper Engine video item gives its file, with the project's title and preview`() throws {
        try folder.write(Self.videoProject, to: "item/project.json")
        let video = try folder.write(to: "item/rain.webm")
        let preview = try folder.write(to: "item/preview.jpg")
        try folder.write(to: "item/unrelated.mp4")

        let found = try discoverSources(at: folder.folder("item"))

        #expect(found == Discovery(candidates: [ImportCandidate(source: video, name: "Rainy Night", preview: preview)]))
    }

    @Test func `a Wallpaper Engine item with no title is named after its file, and a missing preview is left out`() throws {
        try folder.write(#"{"file": "loop.mp4", "preview": "gone.jpg", "type": "video"}"#, to: "item/project.json")
        let video = try folder.write(to: "item/loop.mp4")

        let found = try discoverSources(at: folder.folder("item"))

        #expect(found == Discovery(candidates: [ImportCandidate(source: video, name: "loop")]))
    }

    @Test func `a Wallpaper Engine scene gives its package, with its project, title and preview`() throws {
        let project = #"{"file": "scene.json", "preview": "preview.jpg", "title": "Lantern Street", "type": "scene"}"#
        try folder.write(project, to: "item/project.json")
        let package = try folder.write(to: "item/scene.pkg")
        let preview = try folder.write(to: "item/preview.jpg")
        try folder.write(to: "item/shaders/blobsSM40/0a1b.dxs")

        let found = try discoverSources(at: folder.folder("item"))

        let scene = SceneItem(project: folder.file("item/project.json"), sceneFile: "scene.json")
        #expect(found == Discovery(candidates: [ImportCandidate(source: package, name: "Lantern Street", preview: preview, scene: scene)]))
    }

    @Test func `a scene with no title is named after its folder, and its package after its scene file`() throws {
        try folder.write(#"{"file": "gifscene.json", "type": "scene"}"#, to: "2987840102/project.json")
        let package = try folder.write(to: "2987840102/gifscene.pkg")

        let found = try discoverSources(at: folder.folder("2987840102"))

        #expect(found.candidates.map(\.source) == [package])
        #expect(found.candidates.map(\.name) == ["2987840102"])
        #expect(found.candidates.map(\.scene?.sceneFile) == ["gifscene.json"])
    }

    static let refused: [Row<String, SkipReason>] = [
        Row("a scene whose files lie loose, with no package", #"{"file": "scene.json", "type": "scene"}"#, .noScenePackage("scene.pkg")),
        Row("a web item, which runs code", #"{"file": "index.html", "type": "web"}"#, .wallpaperEngine(.runsCode("web"))),
        Row("an application, which runs code", #"{"file": "game.exe", "type": "application"}"#, .wallpaperEngine(.runsCode("application"))),
        Row("a project nobody could read", "{", .wallpaperEngine(.malformed)),
        Row("a file that is not there", #"{"file": "gone.mp4", "type": "video"}"#, .missingFile("gone.mp4")),
        Row("a path out of the folder", #"{"file": "../loop.mp4", "type": "video"}"#, .wallpaperEngine(.escapesFolder("../loop.mp4"))),
    ]

    @Test(arguments: refused)
    func `a Wallpaper Engine folder that cannot be imported is skipped with the reason`(row: Row<String, SkipReason>) throws {
        let project = try folder.write(row.input, to: "item/project.json")
        try folder.write(to: "loop.mp4")
        try folder.write(to: "item/scene.json")

        let found = try discoverSources(at: folder.folder("item"))

        #expect(found == Discovery(skipped: [SkippedSource(url: project.deletingLastPathComponent(), reason: row.expected)]))
    }

    @Test func `a link that leads out of the Wallpaper Engine folder is refused`() throws {
        try folder.write(#"{"file": "loop.mp4", "type": "video"}"#, to: "item/project.json")
        let outside = try folder.write(to: "outside.mp4")
        try FileManager.default.createSymbolicLink(at: folder.file("item/loop.mp4"), withDestinationURL: outside)

        let found = try discoverSources(at: folder.folder("item"))

        let refusal = SkippedSource(url: folder.folder("item"), reason: .wallpaperEngine(.escapesFolder("loop.mp4")))
        #expect(found == Discovery(skipped: [refusal]))
    }

    @Test func `a project that is a link out of the Wallpaper Engine folder is refused`() throws {
        let outside = try folder.write(#"{"file": "scene.json", "type": "scene"}"#, to: "elsewhere/project.json")
        try folder.write(to: "item/scene.pkg")
        try FileManager.default.createSymbolicLink(at: folder.file("item/project.json"), withDestinationURL: outside)

        let found = try discoverSources(at: folder.folder("item"))

        let refusal = SkippedSource(url: folder.folder("item"), reason: .wallpaperEngine(.escapesFolder("project.json")))
        #expect(found == Discovery(skipped: [refusal]))
    }

    @Test func `a folder of Workshop items gives the video and scene items and says which it left out`() throws {
        try folder.write(Self.videoProject, to: "431960/111/project.json")
        try folder.write(to: "431960/111/rain.webm")
        try folder.write(#"{"file": "index.html", "type": "web"}"#, to: "431960/222/project.json")
        try folder.write(to: "431960/222/materials/loop.mp4")
        try folder.write(#"{"file": "scene.json", "title": "Lantern Street", "type": "scene"}"#, to: "431960/333/project.json")
        try folder.write(to: "431960/333/scene.pkg")
        try folder.write(to: "431960/loose.mov")

        let found = try discoverSources(at: folder.folder("431960"))

        #expect(found.candidates.map(\.name) == ["loose", "Rainy Night", "Lantern Street"])
        #expect(found.skipped == [SkippedSource(url: folder.folder("431960/222"), reason: .wallpaperEngine(.runsCode("web")))])
    }

    @Test func `nothing there is an error, not an empty answer`() {
        #expect(throws: DiscoverError.notFound(folder.file("gone.mp4"))) {
            try discoverSources(at: folder.file("gone.mp4"))
        }
    }
}
