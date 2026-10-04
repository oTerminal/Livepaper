import Foundation
import Testing
import LivepaperCore

struct StatusReportTests {
    static let builtIn = DisplayIdentity.numbered(1)
    static let studio = DisplayIdentity.numbered(2)
    static let evening = PlaylistID.numbered(1)

    static func report(host: RenderHostStatus = .live) throws -> StatusReport {
        let library = try Library.of(.numbered(1, name: "Ocean"), .numbered(2, name: "Forest"))
        var state = AppState()
        state.playlists = [Playlist(id: evening, name: "Evening", wallpapers: [.numbered(2)], interval: .seconds(60), shuffle: false)]
        state.applyToAll = .wallpaper(.numbered(1))
        state.assignments = [studio: .playlist(evening)]
        state.pausedDisplays = [studio]
        state.isMuted = true
        // Given in the order macOS lists them, which is not the file order.
        return StatusReport(
            host: host,
            displays: [studio: "Studio Display", builtIn: "Built-in Retina Display"],
            library: library,
            state: state,
            isPausedAll: false
        )
    }

    @Test func `a report says what the app shows, from the library and the app state`() throws {
        let report = try Self.report()

        #expect(report.host == .live)
        #expect(report.displays == [
            StatusReport.Display(
                id: Self.builtIn, name: "Built-in Retina Display", assignment: .wallpaper(.numbered(1)), isPaused: false
            ),
            StatusReport.Display(id: Self.studio, name: "Studio Display", assignment: .playlist(Self.evening), isPaused: true),
        ])
        #expect(report.wallpapers == [
            StatusReport.Named(id: .numbered(1), name: "Ocean"), StatusReport.Named(id: .numbered(2), name: "Forest"),
        ])
        #expect(report.playlists == [StatusReport.Named(id: Self.evening, name: "Evening")])
        #expect(!report.isPausedAll)
        #expect(report.isMuted)
    }

    @Test func `a display with nothing assigned shows nothing`() {
        let report = StatusReport(
            host: .notSelected,
            displays: [Self.builtIn: "Built-in Retina Display"],
            library: Library(),
            state: AppState(),
            isPausedAll: true
        )

        #expect(report.displays == [
            StatusReport.Display(id: Self.builtIn, name: "Built-in Retina Display", assignment: nil, isPaused: false),
        ])
        #expect(report.isPausedAll)
    }

    @Test func `a report is one JSON line with its keys sorted`() throws {
        let json = try #require(String(bytes: try Self.report().encoded(), encoding: .utf8))

        #expect(json == """
            {"displays":[\
            {"assignment":{"wallpaper":"AAAAAAAA-0000-0000-0000-000000000001"},"id":"DDDDDDDD-0000-0000-0000-000000000001",\
            "isPaused":false,"name":"Built-in Retina Display"},\
            {"assignment":{"playlist":"BBBBBBBB-0000-0000-0000-000000000001"},"id":"DDDDDDDD-0000-0000-0000-000000000002",\
            "isPaused":true,"name":"Studio Display"}\
            ],"host":"live","isMuted":true,"isPausedAll":false,\
            "playlists":[{"id":"BBBBBBBB-0000-0000-0000-000000000001","name":"Evening"}],\
            "wallpapers":[{"id":"AAAAAAAA-0000-0000-0000-000000000001","name":"Ocean"},\
            {"id":"AAAAAAAA-0000-0000-0000-000000000002","name":"Forest"}]}
            """)
    }

    static let hosts: [RenderHostStatus] =
        [.stopped, .connecting, .notSelected, .live, .unavailable] + RecoveryLevel.allCases.map { .recovering($0) }

    @Test(arguments: hosts)
    func `a report decodes to what was encoded, whatever the host says`(host: RenderHostStatus) throws {
        let report = try Self.report(host: host)

        #expect(try StatusReport.decode(report.encoded()) == report)
    }

    @Test func `a host status it does not know does not decode`() throws {
        let json = try #require(String(bytes: try Self.report().encoded(), encoding: .utf8))
            .replacingOccurrences(of: #""host":"live""#, with: #""host":"dancing""#)

        #expect(throws: DecodingError.self) { try StatusReport.decode(Data(json.utf8)) }
    }

    // MARK: The reply

    static let replies: [Row<CommandReply, String>] = [
        Row("done", .done(message: nil), #"{"ok":true}"#),
        Row(
            "done, saying what was done",
            .done(message: "Studio Display now shows “Ocean”."),
            #"{"message":"Studio Display now shows “Ocean”.","ok":true}"#
        ),
        Row(
            "diagnostics, lines and all",
            .diagnostics("Livepaper 0.1.0 (1)\nmacOS 26.0\n"),
            #"{"diagnostics":"Livepaper 0.1.0 (1)\nmacOS 26.0\n","ok":true}"#
        ),
        Row(
            "refused",
            .refused(reason: "No wallpaper or playlist is called “Sea”"),
            #"{"ok":false,"reason":"No wallpaper or playlist is called “Sea”"}"#
        ),
    ]

    @Test(arguments: replies)
    func `a reply is one JSON line`(row: Row<CommandReply, String>) throws {
        let line = try row.input.line()

        #expect(String(bytes: line, encoding: .utf8) == row.expected + "\n")
        #expect(try CommandReply(line: line) == row.input)
    }

    @Test func `a status reply carries the report`() throws {
        let report = try Self.report()
        let line = try CommandReply.status(report).line()
        let json = try #require(String(bytes: line, encoding: .utf8))

        #expect(json.hasPrefix(#"{"ok":true,"status":{"displays":"#))
        #expect(json.filter { $0 == "\n" } == "\n")
        #expect(try CommandReply(line: line) == .status(report))
    }

    @Test func `a rejection is refused with its reason`() {
        #expect(CommandReply.refused(CommandRejection.fragment) == .refused(reason: "A command has no fragment"))
    }

    @Test(arguments: [
        "hello",
        #"{"message":"no ok"}"#,
        #"{"ok":false}"#,
        #"{"diagnostics":"both","ok":true,"status":{}}"#,
    ])
    func `a reply that is not one does not decode`(line: String) {
        #expect(throws: (any Error).self) { try CommandReply(line: Data(line.utf8)) }
    }
}
