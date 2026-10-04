import Foundation
import Testing
import LivepaperCore

struct CommandTests {
    static let ocean = WallpaperID.numbered(1)
    static let evening = PlaylistID.numbered(1)
    static let studio = DisplayIdentity.numbered(2)

    // MARK: Every verb, both ways

    static let verbs: [Row<String, Command>] = [
        Row("set a wallpaper everywhere", "livepaper://set?wallpaper=\(ocean)", .set(.wallpaper(ocean), on: .all)),
        Row(
            "set a playlist on one display",
            "livepaper://set?playlist=\(evening)&display=\(studio)",
            .set(.playlist(evening), on: .display(studio))
        ),
        Row("pause all", "livepaper://pause", .pause(.all)),
        Row("pause one display", "livepaper://pause?display=\(studio)", .pause(.display(studio))),
        Row("resume all", "livepaper://resume", .resume(.all)),
        Row("resume one display", "livepaper://resume?display=\(studio)", .resume(.display(studio))),
        Row("next everywhere", "livepaper://next", .next(.all)),
        Row("next on one display", "livepaper://next?display=\(studio)", .next(.display(studio))),
        Row("mute", "livepaper://mute", .mute),
        Row("unmute", "livepaper://unmute", .unmute),
        Row("the library window", "livepaper://library", .library),
        Row("Settings", "livepaper://settings", .settings),
        Row("diagnostics", "livepaper://diagnostics", .diagnostics),
        Row("status", "livepaper://status", .status),
    ]

    @Test(arguments: verbs)
    func `every verb parses and renders back to the same URL`(row: Row<String, Command>) throws {
        let url = try #require(URL(string: row.input))

        #expect(try Command(url: url) == row.expected)
        #expect(try Command(string: row.input) == row.expected)
        #expect(row.expected.url.absoluteString == row.input)
    }

    @Test func `every verb has a row`() {
        #expect(Set(Self.verbs.map(\.expected.verb)) == Set(Command.Verb.allCases))
    }

    static let alsoAccepted: [Row<String, Command>] = [
        Row("display=all, which is the default", "livepaper://pause?display=all", .pause(.all)),
        Row("set with display=all", "livepaper://set?wallpaper=\(ocean)&display=all", .set(.wallpaper(ocean), on: .all)),
        Row(
            "the display before the playlist",
            "livepaper://set?display=\(studio)&playlist=\(evening)",
            .set(.playlist(evening), on: .display(studio))
        ),
        Row("a UUID in lower case", "livepaper://set?wallpaper=\(ocean.description.lowercased())", .set(.wallpaper(ocean), on: .all)),
        Row("the scheme in capitals, which is the same scheme", "LIVEPAPER://mute", .mute),
        Row("an empty query", "livepaper://mute?", .mute),
    ]

    @Test(arguments: alsoAccepted)
    func `accepts another spelling of the same command`(row: Row<String, Command>) throws {
        #expect(try Command(string: row.input) == row.expected)
    }

    // MARK: Rejections

    static let rejected: [Row<String, CommandRejection>] = [
        Row("another scheme", "https://pause", .notLivepaper),
        Row("not a URL at all", "hello", .notLivepaper),
        Row("an empty line", "", .notLivepaper),
        Row("no verb", "livepaper://", .noVerb),
        Row("an unknown verb", "livepaper://play", .unknownVerb("play")),
        Row("a verb in capitals", "livepaper://PAUSE", .unknownVerb("PAUSE")),
        Row("a verb that runs something", "livepaper://open?file=/Applications/Calculator.app", .unknownVerb("open")),
        // Importing is done in the app's window alone: no link or tool names a file for it.
        Row("import", "livepaper://import?file=/Users/sam/Movies/Ocean.mov", .unknownVerb("import")),
        Row("import that would set everywhere", "livepaper://import?file=/Users/sam/Movies/Ocean.mov&set=all", .unknownVerb("import")),
        Row("a path", "livepaper://pause/now", .path("/now")),
        Row("a trailing slash is a path", "livepaper://pause/", .path("/")),
        Row("a path climbing out", "livepaper://set/../x", .path("/../x")),
        Row("a verb written as a path", "livepaper:pause", .path("pause")),
        Row("a fragment", "livepaper://pause#now", .fragment),
        Row("an empty fragment", "livepaper://mute#", .fragment),
        Row("a port", "livepaper://pause:1", .port),
        Row("a user name", "livepaper://sam@pause", .credentials),
        Row("a user name and a password", "livepaper://sam:secret@pause", .credentials),
        Row("a key the verb does not take", "livepaper://pause?file=/a.mov", .unknownKey(verb: .pause, key: "file")),
        Row("a key on a verb that takes none", "livepaper://mute?display=all", .unknownKey(verb: .mute, key: "display")),
        Row("status takes no key", "livepaper://status?verbose=1", .unknownKey(verb: .status, key: "verbose")),
        Row("set takes no file", "livepaper://set?wallpaper=\(ocean)&file=/a.mov", .unknownKey(verb: .set, key: "file")),
        Row("an empty key", "livepaper://pause?&", .unknownKey(verb: .pause, key: "")),
        Row("a key in capitals", "livepaper://pause?Display=all", .unknownKey(verb: .pause, key: "Display")),
        Row("a display given twice", "livepaper://pause?display=all&display=all", .repeatedKey("display")),
        Row("a wallpaper given twice", "livepaper://set?wallpaper=\(ocean)&wallpaper=\(ocean)", .repeatedKey("wallpaper")),
        Row("set names nothing", "livepaper://set", .needsWallpaperOrPlaylist),
        Row("set names only a display", "livepaper://set?display=all", .needsWallpaperOrPlaylist),
        Row(
            "set names a wallpaper and a playlist",
            "livepaper://set?wallpaper=\(ocean)&playlist=\(evening)",
            .needsWallpaperOrPlaylist
        ),
        Row("a wallpaper named by path", "livepaper://set?wallpaper=../x", .notAUUID(key: "wallpaper", value: "../x")),
        Row("a playlist named by name", "livepaper://set?playlist=Evening", .notAUUID(key: "playlist", value: "Evening")),
        Row("a wallpaper cannot be all", "livepaper://set?wallpaper=all", .notAUUID(key: "wallpaper", value: "all")),
        Row("a display named by name", "livepaper://set?wallpaper=\(ocean)&display=Studio", .notAUUID(key: "display", value: "Studio")),
        Row("an empty display", "livepaper://next?display=", .notAUUID(key: "display", value: "")),
        Row("a UUID with a brace", "livepaper://pause?display={\(studio)}", .notAUUID(key: "display", value: "{\(studio)}")),
    ]

    @Test(arguments: rejected)
    func `rejects anything else with a reason`(row: Row<String, CommandRejection>) {
        #expect(throws: row.expected) { try Command(string: row.input) }
        if let url = URL(string: row.input) {
            #expect(throws: row.expected) { try Command(url: url) }
        }
    }

    @Test(arguments: rejected)
    func `a rejection says why in a sentence`(row: Row<String, CommandRejection>) {
        let reason = row.expected.reason

        #expect(!reason.isEmpty)
        #expect(reason.first?.isUppercase == true || reason.first == "“")
        #expect(!reason.contains("\n"))
    }

    /// What the sender wrote that a rejection carries: anything, since any web page can open a link.
    static func written(_ rejection: CommandRejection) -> String? {
        switch rejection {
        case .unknownVerb(let text), .path(let text), .unknownKey(_, let text), .notAUUID(_, let text): text
        default: nil
        }
    }

    @Test(arguments: rejected)
    func `a rejection is logged by its kind, repeating nothing the sender wrote`(row: Row<String, CommandRejection>) {
        let kind = row.expected.kind

        #expect(!kind.isEmpty)
        #expect(!kind.contains("\n"))
        // A value as short as “all” is the grammar's own word, and in “wallpaper” besides.
        if let written = Self.written(row.expected), written.count > 3 {
            #expect(!kind.contains(written))
        }
    }

    @Test func `a rejection repeats a long value only in part`() {
        let junk = String(repeating: "x", count: 10_000)
        let rejection = CommandRejection.unknownVerb(junk)

        #expect(rejection.reason.count < 120)
    }
}
