import Foundation
import Testing
import LivepaperCore

struct CommandLineRequestTests {
    static let builtIn = DisplayIdentity.numbered(1)
    static let studio = DisplayIdentity.numbered(2)
    static let evening = PlaylistID.numbered(1)
    static let rain = PlaylistID.numbered(2)

    static func named(_ number: Int, _ name: String) -> StatusReport.Named<WallpaperID> {
        StatusReport.Named(id: .numbered(number), name: name)
    }

    /// What `status` answered.
    static let report = StatusReport(
        host: .live,
        displays: [
            StatusReport.Display(id: builtIn, name: "Built-in Retina Display", assignment: .wallpaper(.numbered(1)), isPaused: false),
            StatusReport.Display(id: studio, name: "Studio Display", assignment: .playlist(evening), isPaused: true),
        ],
        wallpapers: [
            named(1, "Ocean"), named(2, "Forest"), named(3, "Caf\u{E9}"), named(4, "Sunset"), named(5, "Sunset"),
            named(6, "Evening Sky"), named(7, "Rain"), named(8, "Moon"), named(9, "moon"),
        ],
        playlists: [StatusReport.Named(id: evening, name: "Evening"), StatusReport.Named(id: rain, name: "Rain")],
        isPausedAll: false,
        isMuted: true
    )

    static func request(_ arguments: [String]) throws(CommandLineUsageError) -> CommandLineRequest {
        try CommandLineRequest(arguments: arguments)
    }

    /// What the tool sends for the request: for `set <name>`, what it sends once `status` has answered.
    static func sent(_ request: CommandLineRequest) throws -> String? {
        switch request {
        case .help: nil
        case .status: Command.status.url.absoluteString
        case .send(let command): command.url.absoluteString
        case .set(let name, let target): Command.set(try report.assignment(named: name), on: target).url.absoluteString
        }
    }

    // MARK: Each command, as the URL it sends

    static let commands: [Row<[String], String>] = [
        Row("status", ["status"], "livepaper://status"),
        Row("status as JSON", ["status", "--json"], "livepaper://status"),
        Row("set a wallpaper by name, everywhere", ["set", "Ocean"], "livepaper://set?wallpaper=AAAAAAAA-0000-0000-0000-000000000001"),
        Row(
            "set a playlist by name, on one display",
            ["set", "Evening", "--display", studio.description],
            "livepaper://set?playlist=BBBBBBBB-0000-0000-0000-000000000001&display=\(studio)"
        ),
        Row(
            "set by UUID",
            ["set", "aaaaaaaa-0000-0000-0000-000000000002", "--display=\(builtIn)"],
            "livepaper://set?wallpaper=AAAAAAAA-0000-0000-0000-000000000002&display=\(builtIn)"
        ),
        Row("pause all", ["pause"], "livepaper://pause"),
        Row("pause one display", ["pause", "--display", studio.description], "livepaper://pause?display=\(studio)"),
        Row("--display all is every display", ["pause", "--display", "all"], "livepaper://pause"),
        Row("resume one display", ["resume", "--display=\(studio)"], "livepaper://resume?display=\(studio)"),
        Row("next", ["next"], "livepaper://next"),
        Row("next on one display", ["next", "--display", builtIn.description], "livepaper://next?display=\(builtIn)"),
        Row("mute", ["mute"], "livepaper://mute"),
        Row("unmute", ["unmute"], "livepaper://unmute"),
        Row("the library window", ["library"], "livepaper://library"),
        Row("Settings", ["settings"], "livepaper://settings"),
        Row("diagnostics", ["diagnostics"], "livepaper://diagnostics"),
    ]

    @Test(arguments: commands)
    func `each command maps to the URL it sends`(row: Row<[String], String>) throws {
        #expect(try Self.sent(Self.request(row.input)) == row.expected)
    }

    @Test func `status prints JSON only when asked`() throws {
        #expect(try Self.request(["status"]) == .status(json: false))
        #expect(try Self.request(["status", "--json"]) == .status(json: true))
    }

    @Test(arguments: [["help"], ["--help"], ["-h"], ["help", "set"]])
    func `help sends nothing`(arguments: [String]) throws {
        #expect(try Self.request(arguments) == .help)
    }

    // MARK: Usage errors

    static let usage: [Row<[String], CommandLineUsageError>] = [
        Row("nothing", [], .noCommand),
        Row("an unknown command", ["play"], .unknownCommand("play")),
        // Importing is done in the app's window alone.
        Row("import", ["import", "Ocean.mov"], .unknownCommand("import")),
        Row("import that would set everywhere", ["import", "Ocean.mov", "--set"], .unknownCommand("import")),
        Row("an unknown option", ["status", "--jsn"], .unknownOption(command: "status", option: "--jsn")),
        Row("--json given twice", ["status", "--json", "--json"], .repeatedOption("--json")),
        Row("set with no name", ["set"], .noName),
        Row("set with an empty name", ["set", " "], .emptyArgument),
        Row("set with two names", ["set", "Ocean", "Forest"], .unexpectedArgument(command: "set", argument: "Forest")),
        Row("--display with no value", ["pause", "--display"], .missingValue("--display")),
        Row("--display= with no value", ["pause", "--display="], .notADisplay("")),
        Row("a display by name", ["pause", "--display", "Studio"], .notADisplay("Studio")),
        Row("--display given twice", ["next", "--display", "all", "--display", "all"], .repeatedOption("--display")),
        Row("an argument pause does not take", ["pause", "now"], .unexpectedArgument(command: "pause", argument: "now")),
        Row("mute takes no display", ["mute", "--display", "all"], .unknownOption(command: "mute", option: "--display")),
        Row("library takes nothing", ["library", "Ocean"], .unexpectedArgument(command: "library", argument: "Ocean")),
        Row("status takes no other format", ["status", "--yaml"], .unknownOption(command: "status", option: "--yaml")),
        Row("set takes no --set", ["set", "Ocean", "--set"], .unknownOption(command: "set", option: "--set")),
    ]

    @Test(arguments: usage)
    func `a usage error says what is wrong`(row: Row<[String], CommandLineUsageError>) {
        #expect(throws: row.expected) { try Self.request(row.input) }
        #expect(!row.expected.message.isEmpty)
    }

    // MARK: A name, resolved against status

    static let names: [Row<String, Assignment>] = [
        Row("a wallpaper by its name", "Ocean", .wallpaper(.numbered(1))),
        Row("a playlist by its name", "Evening", .playlist(evening)),
        Row("a name in another case, when only one matches", "forest", .wallpaper(.numbered(2))),
        Row("a name without its accent", "cafe", .wallpaper(.numbered(3))),
        Row("spaces around the name", "  Ocean ", .wallpaper(.numbered(1))),
        Row("the exact name beats one in another case", "moon", .wallpaper(.numbered(9))),
        Row("a wallpaper by its UUID", "AAAAAAAA-0000-0000-0000-000000000004", .wallpaper(.numbered(4))),
        Row("a playlist by its UUID in lower case", "bbbbbbbb-0000-0000-0000-000000000002", .playlist(rain)),
        Row("a whole name, never a part of one", "Evening Sky", .wallpaper(.numbered(6))),
    ]

    @Test(arguments: names)
    func `set resolves a name against status`(row: Row<String, Assignment>) throws {
        #expect(try Self.report.assignment(named: row.input) == row.expected)
    }

    static let unresolved: [Row<String, AssignmentNameError>] = [
        Row("no such name", "Sea", .notFound("Sea")),
        Row("part of a name", "Even", .notFound("Even")),
        Row("a UUID the library does not hold", "AAAAAAAA-0000-0000-0000-000000000099", .notFound("AAAAAAAA-0000-0000-0000-000000000099")),
        Row(
            "two wallpapers with the name",
            "Sunset",
            .ambiguous("Sunset", [.wallpaper(.numbered(4)), .wallpaper(.numbered(5))])
        ),
        Row("a wallpaper and a playlist with the name", "Rain", .ambiguous("Rain", [.wallpaper(.numbered(7)), .playlist(rain)])),
        Row(
            "two names that differ only in case, neither exact",
            "MOON",
            .ambiguous("MOON", [.wallpaper(.numbered(8)), .wallpaper(.numbered(9))])
        ),
    ]

    @Test(arguments: unresolved)
    func `set refuses a name that names nothing, or more than one thing`(row: Row<String, AssignmentNameError>) {
        #expect(throws: row.expected) { try Self.report.assignment(named: row.input) }
    }

    @Test func `an ambiguous name is refused with the UUIDs to use instead`() {
        let error = AssignmentNameError.ambiguous("Rain", [.wallpaper(.numbered(7)), .playlist(Self.rain)])

        #expect(error.reason == "“Rain” names more than one thing; use a UUID: wallpaper AAAAAAAA-0000-0000-0000-000000000007, "
            + "playlist BBBBBBBB-0000-0000-0000-000000000002")
        #expect(AssignmentNameError.notFound("Sea").reason == "No wallpaper or playlist is called “Sea”")
    }

    @Test func `the usage names every command`() {
        for command in Command.Verb.allCases.map(\.rawValue) + ["help"] {
            #expect(CommandLineRequest.usage.contains("\n  \(command) "))
        }
    }

    @Test func `the usage offers no import, and says where importing is done`() {
        #expect(!CommandLineRequest.usage.contains("\n  import "))
        #expect(CommandLineRequest.usage.contains("Wallpapers are imported in Livepaper's window, not here."))
    }
}
