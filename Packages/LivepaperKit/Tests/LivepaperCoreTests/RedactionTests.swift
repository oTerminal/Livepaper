import Foundation
import Testing
import LivepaperCore

/// A diagnostics report never says who the user is, what their wallpapers are
/// called or where their files are.
struct RedactionTests {
    static let redaction = Redaction(
        home: "/Users/jappleseed",
        userNames: ["jappleseed", "Johnny Appleseed", "applefan42"],
        wallpaperNames: ["Evening Tide", "Sun"],
        fileNames: ["Beach Holiday.mov", "wallpaper.mov", "poster.heic"]
    )

    static let rows: [Row<String, String>] = [
        Row(
            "the home path, and the path under it",
            "extension: launched pid=12 version=0.1.0 build=1 bundle=/Users/jappleseed/Applications/Livepaper.app/Contents/X.appex",
            "extension: launched pid=12 version=0.1.0 build=1 bundle=<path>"
        ),
        Row("the home path on its own", "home is /Users/jappleseed here", "home is <path> here"),
        Row("the home as a tilde", "reading ~/Library/Application Support/Livepaper", "reading <path> Support/Livepaper"),
        Row("another user's home as a tilde", "not ~jappleseed/Movies", "not <path>"),
        Row("any other path", "bundle=/Applications/Livepaper.app/Contents", "bundle=<path>"),
        Row("a path in a file URL", "cannot read file:///Volumes/Backup/clip.mov", "cannot read file://<path>"),
        Row("the user's short name", "owner jappleseed, uid 501", "owner <user>, uid 501"),
        Row("the user's full name, in any case", "by JOHNNY APPLESEED", "by <user>"),
        Row("the Steam account's name", "signed in as applefan42.", "signed in as <user>."),
        Row("a wallpaper's name", "now showing \"Evening Tide\" on display 1", "now showing \"<wallpaper>\" on display 1"),
        Row(
            "a library file's name",
            "on AAAAAAAA-0000-0000-0000-000000000001/wallpaper.mov: loops 20",
            "on AAAAAAAA-0000-0000-0000-000000000001/<file>: loops 20"
        ),
        Row("a source file's name", "import failed for Beach Holiday.mov", "import failed for <file>"),
        Row("a source file's name in a path with a space", "at /Users/jappleseed/Movies/Beach Holiday.mov now", "at <path> now"),
        Row("what the log hid", "acquired <private> for surface 3", "acquired <hidden> for surface 3"),
        Row("a word that only holds a name is kept", "Sunday and sunset", "Sunday and sunset"),
        Row(
            "the rest is kept as it was",
            "decision display=DDDDDDDD-0000-0000-0000-000000000001 decision=pause.user generation=12, 12/20 ok",
            "decision display=DDDDDDDD-0000-0000-0000-000000000001 decision=pause.user generation=12, 12/20 ok"
        ),
        Row(
            "the self-check's names",
            "bridge self-check: usable, missing: +[CAContext remoteContextWithOptions:], WallpaperSnapshotXPC.rawValue",
            "bridge self-check: usable, missing: +[CAContext remoteContextWithOptions:], WallpaperSnapshotXPC.rawValue"
        ),
    ]

    @Test(arguments: rows)
    func `a line keeps what it says and loses who and where`(row: Row<String, String>) {
        #expect(Self.redaction.redact(row.input) == row.expected)
    }

    @Test func `a name that is also a placeholder's word does not break the placeholder`() {
        let redaction = Redaction(home: "/Users/path", userNames: ["user", "hidden"], wallpaperNames: ["file"], fileNames: ["wallpaper"])

        #expect(redaction.redact("/Users/path/x user file wallpaper <private>") == "<path> <user> <wallpaper> <file> <hidden>")
    }

    @Test func `empty names redact nothing`() {
        let redaction = Redaction(home: "", userNames: ["", "  "], wallpaperNames: [""], fileNames: [])

        #expect(redaction.redact("a line with nothing to hide") == "a line with nothing to hide")
    }

    @Test func `the library gives every wallpaper's name and file names`() throws {
        let wallpaper = Wallpaper(
            id: .numbered(1),
            name: "Evening Tide",
            importedAt: Moment.launch,
            fingerprint: Fingerprint(sha256: String(repeating: "0", count: 64)),
            optimisedCopy: .known("wallpapers/AAAAAAAA-0000-0000-0000-000000000001/wallpaper.mov"),
            poster: .known("wallpapers/AAAAAAAA-0000-0000-0000-000000000001/poster.heic"),
            hoverPreview: .known("wallpapers/AAAAAAAA-0000-0000-0000-000000000001/hover.mov"),
            details: WallpaperDetails(duration: 1, width: 1, height: 1, frameRate: 1, codec: "hevc", byteCount: 1),
            scene: WallpaperScene(project: .known("wallpapers/1/scene/project.json"), width: 1, height: 1)
        )
        let library = try Library.of(wallpaper)
        let redaction = Redaction(home: "/Users/jappleseed", userNames: [], library: library, sourceFileNames: ["Tide.mp4"])

        #expect(
            redaction.redact("Evening Tide: wallpaper.mov poster.heic hover.mov project.json Tide.mp4")
                == "<wallpaper>: <file> <file> <file> <file> <file>"
        )
    }
}
