import Foundation
import Testing
import LivepaperImport

struct WallpaperEngineProjectTests {
    typealias Outcome = Result<WallpaperEngineProject, WallpaperEngineProjectError>

    static let rows: [Row<String, Outcome>] = [
        Row(
            "a video item gives its file, title and preview",
            #"{"file": "rain.mp4", "preview": "preview.jpg", "title": "Rainy Night", "type": "video", "workshopid": "123"}"#,
            .success(.known(title: "Rainy Night", file: "rain.mp4", preview: "preview.jpg"))
        ),
        Row(
            "the type is matched whatever its case",
            #"{"file": "loop.webm", "type": "Video"}"#,
            .success(.known(file: "loop.webm"))
        ),
        Row(
            "a blank title counts as no title",
            #"{"file": "loop.webm", "title": "  ", "type": "video"}"#,
            .success(.known(file: "loop.webm"))
        ),
        Row(
            "a file in a subfolder, written the Windows way",
            #"{"file": "media\\loop.mp4", "type": "video"}"#,
            .success(.known(file: "media/loop.mp4"))
        ),
        Row(
            "a preview that escapes the folder is dropped, the item is still good",
            #"{"file": "loop.mp4", "preview": "../../secret.png", "type": "video"}"#,
            .success(.known(file: "loop.mp4"))
        ),
        Row(
            "a scene gives its JSON, which is in its package",
            #"{"file": "scene.json", "preview": "preview.jpg", "title": "Lantern Street", "type": "scene"}"#,
            .success(.known(kind: .scene, title: "Lantern Street", file: "scene.json", preview: "preview.jpg"))
        ),
        Row(
            "a scene made from the GIF template",
            #"{"file": "gifscene.json", "type": "Scene"}"#,
            .success(.known(kind: .scene, file: "gifscene.json"))
        ),
        Row("a web item is refused: it runs code", #"{"file": "index.html", "type": "web"}"#, .failure(.runsCode("web"))),
        Row("an application is refused: it runs code", #"{"file": "game.exe", "type": "application"}"#, .failure(.runsCode("application"))),
        Row("a type nobody knows", #"{"file": "x.json", "type": "preset"}"#, .failure(.unsupportedType("preset"))),
        Row("no type at all", #"{"file": "loop.mp4"}"#, .failure(.malformed)),
        Row("a type that is not a string", #"{"file": "loop.mp4", "type": 3}"#, .failure(.malformed)),
        Row("not JSON", "type: video", .failure(.malformed)),
        Row("JSON that is not an object", #"["video"]"#, .failure(.malformed)),
        Row("an empty file", "", .failure(.malformed)),
        Row("a video item that names no file", #"{"type": "video"}"#, .failure(.noFile)),
        Row("a video item with an empty file name", #"{"file": "", "type": "video"}"#, .failure(.noFile)),
        Row("a parent step", #"{"file": "../other/loop.mp4", "type": "video"}"#, .failure(.escapesFolder("../other/loop.mp4"))),
        Row(
            "a parent step in the middle, written the Windows way",
            #"{"file": "media\\..\\..\\loop.mp4", "type": "video"}"#,
            .failure(.escapesFolder("media\\..\\..\\loop.mp4"))
        ),
        Row("an absolute path", #"{"file": "/etc/passwd", "type": "video"}"#, .failure(.escapesFolder("/etc/passwd"))),
        Row("a drive letter", #"{"file": "C:\\Windows\\loop.mp4", "type": "video"}"#, .failure(.escapesFolder("C:\\Windows\\loop.mp4"))),
        Row("the home shorthand", #"{"file": "~/Movies/loop.mp4", "type": "video"}"#, .failure(.escapesFolder("~/Movies/loop.mp4"))),
    ]

    @Test func `a project cannot be made around a path that leads out of its folder`() {
        #expect(throws: WallpaperEngineProjectError.escapesFolder("../loop.mp4")) {
            try WallpaperEngineProject(title: nil, file: "../loop.mp4", preview: nil)
        }
    }

    @Test(arguments: rows)
    func `reads a project.json`(row: Row<String, Outcome>) {
        let outcome = Outcome { () throws(WallpaperEngineProjectError) in
            try WallpaperEngineProject.parse(Data(row.input.utf8))
        }

        #expect(outcome == row.expected)
    }
}
