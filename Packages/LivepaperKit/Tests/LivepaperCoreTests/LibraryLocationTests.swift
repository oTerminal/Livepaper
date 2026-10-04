import Foundation
import Testing
import LivepaperCore

struct LibraryLocationTests {
    static let home = URL(filePath: "/Users/sam", directoryHint: .isDirectory)
    static let location = LibraryLocation(home: home)
    static let root = "/Users/sam/Library/Application Support/Livepaper"

    @Test func `the library is in the caller's home, never the sandbox container's`() {
        #expect(Self.location.root.path == Self.root)
    }

    @Test func `the same home gives the same library, whatever is on the disk`() {
        // Foundation's own standardising drops `/private` only when the path exists.
        let home = URL(filePath: "/private/var/nobody-\(UInt64.max)/home", directoryHint: .isDirectory)
        let location = LibraryLocation(home: home)

        #expect(location == LibraryLocation(home: home))
        #expect(location.root.path == "/private/var/nobody-\(UInt64.max)/home/Library/Application Support/Livepaper")
        #expect(throws: Never.self) { try location.resolve("library.json") }
    }

    @Test func `a home written with parent steps is worked out by name`() {
        let location = LibraryLocation(home: URL(filePath: "/Users/alex/../sam/./", directoryHint: .isDirectory))

        #expect(location == Self.location)
    }

    @Test func `the staging folder is inside the root`() {
        #expect(Self.location.staging.path == Self.root + "/.staging")
        #expect(Self.location.contains(Self.location.staging))
    }

    @Test func `the wallpapers' folders are inside the root, where the manifest's paths point`() throws {
        #expect(Self.location.wallpapers.path == Self.root + "/wallpapers")
        #expect(try Self.location.resolve("wallpapers/AAAAAAAA-0000-0000-0000-000000000001/wallpaper.mov").path
            .hasPrefix(Self.location.wallpapers.path + "/"))
    }

    @Test func `the manifest and the render state are inside the root`() {
        #expect(Self.location.manifest.path == Self.root + "/library.json")
        #expect(Self.location.renderState.path == Self.root + "/render-state.json")
    }

    @Test func `the app state is beside the manifest`() {
        #expect(Self.location.appState.path == Self.root + "/app-state.json")
    }

    @Test func `the kept wallpaper store and the command socket are inside the root`() {
        #expect(Self.location.keptWallpaperStore.path == Self.root + "/wallpaper-store-before-livepaper.plist")
        #expect(Self.location.commandSocket.path == Self.root + "/command.sock")
    }

    static let accepted: [Row<String, String>] = [
        Row("a file at the root", "library.json", root + "/library.json"),
        Row(
            "a wallpaper's optimised copy",
            "wallpapers/AAAAAAAA-0000-0000-0000-000000000001/wallpaper.mov",
            root + "/wallpapers/AAAAAAAA-0000-0000-0000-000000000001/wallpaper.mov"
        ),
        Row("a name with dots that is not a dot name", "wallpapers/a..b/poster.v2.heic", root + "/wallpapers/a..b/poster.v2.heic"),
    ]

    @Test(arguments: accepted)
    func `resolves a path inside the library`(row: Row<String, String>) throws {
        let url = try Self.location.resolve(row.input)

        #expect(url.path == row.expected)
        #expect(Self.location.contains(url))
    }

    static let rejected: [Row<String, LibraryPathError>] = [
        Row("an empty string", "", .empty),
        Row("only spaces", "   ", .illegalComponent("   ")),
        Row("an absolute path", "/etc/passwd", .absolute),
        Row("an absolute path back into the library", root + "/library.json", .absolute),
        Row("the home shorthand", "~/Library/Keychains/login.keychain-db", .illegalComponent("~")),
        Row("a parent step", "../Livepaper-evil/wallpaper.mov", .illegalComponent("..")),
        Row("a parent step in the middle", "wallpapers/../../../Keychains/x", .illegalComponent("..")),
        Row("a parent step that would normalise back inside", "wallpapers/../library.json", .illegalComponent("..")),
        Row("a trailing parent step", "wallpapers/..", .illegalComponent("..")),
        Row("a current-folder step", "./library.json", .illegalComponent(".")),
        Row("an empty step", "wallpapers//wallpaper.mov", .illegalComponent("")),
        Row("a trailing slash", "wallpapers/", .illegalComponent("")),
        Row("a hidden name, the staging folder included", ".staging/x/wallpaper.mov", .illegalComponent(".staging")),
        Row("a backslash step", "wallpapers\\..\\..\\x", .illegalComponent("wallpapers\\..\\..\\x")),
        Row("a name that reads like a symlink listing", "poster.heic -> /etc/passwd", .illegalComponent("poster.heic -> ")),
        Row("a name with the symlink marker ls prints", "wallpapers/current@", .illegalComponent("current@")),
        Row("an alias-style name", "wallpapers/poster.heic alias", .illegalComponent("poster.heic alias")),
        Row("a NUL that would cut the path short", "wallpapers/a\u{0}/../../x", .illegalComponent("a\u{0}")),
        Row("a newline", "wallpapers/a\nb", .illegalComponent("a\nb")),
        Row("a full-width dot lookalike of a parent step", "wallpapers/\u{FF0E}\u{FF0E}/x", .illegalComponent("\u{FF0E}\u{FF0E}")),
        Row("a slash lookalike", "wallpapers\u{2215}..\u{2215}x", .illegalComponent("wallpapers\u{2215}..\u{2215}x")),
        Row("a colon, the old path separator", "wallpapers:x", .illegalComponent("wallpapers:x")),
        Row("a percent escape", "wallpapers/%2e%2e/x", .illegalComponent("%2e%2e")),
    ]

    @Test(arguments: rejected)
    func `rejects a path that could leave the library`(row: Row<String, LibraryPathError>) {
        #expect(throws: row.expected) { try Self.location.resolve(row.input) }
        #expect(throws: row.expected) { try LibraryPath(row.input) }
    }

    @Test func `a checked path is inside the library by construction`() throws {
        let path = try LibraryPath("wallpapers/AAAAAAAA-0000-0000-0000-000000000001/poster.heic")

        #expect(Self.location.url(for: path).path == Self.root + "/wallpapers/AAAAAAAA-0000-0000-0000-000000000001/poster.heic")
        #expect(Self.location.contains(Self.location.url(for: path)))
    }

    @Test func `a path is checked again when it is decoded`() throws {
        let good = try JSONDecoder().decode([LibraryPath].self, from: Data(#"["wallpapers/x/poster.heic"]"#.utf8))

        #expect(good == [try LibraryPath("wallpapers/x/poster.heic")])
        #expect(throws: LibraryPathError.illegalComponent("..")) {
            try JSONDecoder().decode([LibraryPath].self, from: Data(#"["wallpapers/../../x"]"#.utf8))
        }
    }

    static let outside: [Row<String, Bool>] = [
        Row("the root itself is inside", root, true),
        Row("a file in the root is inside", root + "/wallpapers/x/wallpaper.mov", true),
        Row("a sibling whose name starts the same is outside", root + "-evil/wallpaper.mov", false),
        Row("the parent is outside", "/Users/sam/Library/Application Support", false),
        Row("a path that normalises outside is outside", root + "/wallpapers/../../Keychains/x", false),
        Row("a path that normalises back inside is inside", root + "/wallpapers/../library.json", true),
        Row("another user's library is outside", "/Users/alex/Library/Application Support/Livepaper/library.json", false),
    ]

    @Test(arguments: outside)
    func `knows what is inside the root`(row: Row<String, Bool>) {
        #expect(Self.location.contains(URL(filePath: row.input)) == row.expected)
    }
}
