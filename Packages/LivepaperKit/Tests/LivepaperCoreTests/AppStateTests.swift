import Foundation
import Testing
import LivepaperCore

struct AppStateTests {
    static let evening = Playlist(
        id: .numbered(1), name: "Evening", wallpapers: [.numbered(1), .numbered(2), .numbered(3)], interval: .seconds(1800), shuffle: true
    )
    static let focus = Playlist(id: .numbered(2), name: "Focus", wallpapers: [.numbered(2)], interval: .seconds(90.5), shuffle: false)

    /// What `app-state-v1.0.json` says.
    static var fixtureState: AppState {
        var state = AppState()
        state.assignments = [.numbered(1): .wallpaper(.numbered(1)), .numbered(2): .playlist(.numbered(1))]
        state.applyToAll = .wallpaper(.numbered(2))
        state.playlists = [evening, focus]
        state.rotation = [
            .numbered(2): RotationState(
                current: .numbered(3), position: 2, upcoming: [.numbered(1)], lastRotation: Date(timeIntervalSince1970: 1_789_984_800.25)
            ),
        ]
        state.pauseRules = PauseRules(whenDesktopCovered: true, whenDisplayAsleepOrLocked: false, inLowPowerMode: true, onBattery: true)
        state.pausedDisplays = [.numbered(1)]
        state.isMuted = true
        state.sortOrder = .name
        state.recents = [.numbered(3), .numbered(1)]
        return state
    }

    static func json(_ state: AppState) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: state.encode()) as? [String: Any])
    }

    // MARK: Defaults

    @Test func `a first launch starts with nothing assigned, Core's pause rules, sound on and the newest first`() {
        let state = AppState()

        #expect(state.assignments.isEmpty && state.applyToAll == nil)
        #expect(state.playlists.isEmpty && state.rotation.isEmpty)
        #expect(state.pauseRules == PauseRules())
        #expect(state.pausedDisplays.isEmpty && !state.isMuted)
        #expect(state.sortOrder == .newestFirst)
        #expect(state.recents.isEmpty)
    }

    // MARK: Round trip

    static let roundTrips: [Row<AppState, Void>] = [
        Row("two displays, apply to all, playlists, a rotation, a pause, mute, sort and recents", fixtureState, ()),
        Row("a first launch", AppState(), ()),
        Row(
            "a rotation that has not started, with no optional keys",
            { var state = fixtureState; state.rotation = [.numbered(3): RotationState()]; return state }(),
            ()
        ),
        Row(
            "a playlist as apply to all, oldest first",
            {
                var state = fixtureState
                state.applyToAll = .playlist(.numbered(2))
                state.sortOrder = .oldestFirst
                return state
            }(),
            ()
        ),
        Row(
            "a rotation dated by the real clock, with all its digits",
            {
                var state = AppState()
                let lastRotation = Date(timeIntervalSinceReferenceDate: 811_677_600.123_456_7)
                state.rotation = [.numbered(1): RotationState(current: .numbered(1), lastRotation: lastRotation)]
                return state
            }(),
            ()
        ),
    ]

    @Test(arguments: roundTrips)
    func `survives a round trip`(row: Row<AppState, Void>) throws {
        let decoded = try AppState.decode(row.input.encode())

        #expect(decoded == row.input)
    }

    @Test func `writes its schema version`() throws {
        #expect(try Self.json(Self.fixtureState)["version"] as? [String: Int] == ["major": 1, "minor": 1])
    }

    // MARK: Shapes

    @Test func `an assignment is written as the one thing it names`() throws {
        let json = try Self.json(Self.fixtureState)
        let assignments = try #require(json["assignments"] as? [[String: Any]])

        #expect(assignments.map { $0["display"] as? String } == [1, 2].map { DisplayIdentity.numbered($0).description })
        #expect(assignments.map { $0["assignment"] as? [String: String] } == [
            ["wallpaper": "AAAAAAAA-0000-0000-0000-000000000001"],
            ["playlist": "BBBBBBBB-0000-0000-0000-000000000001"],
        ])
        #expect(json["applyToAll"] as? [String: String] == ["wallpaper": "AAAAAAAA-0000-0000-0000-000000000002"])
    }

    @Test func `no apply to all is written as no key`() throws {
        #expect(try Self.json(AppState())["applyToAll"] == nil)
    }

    @Test func `a playlist's interval is written in seconds`() throws {
        let playlists = try #require(Self.json(Self.fixtureState)["playlists"] as? [[String: Any]])

        #expect(playlists.map { $0["interval"] as? Double } == [1800, 90.5])
        #expect(playlists.map { $0["name"] as? String } == ["Evening", "Focus"])
    }

    @Test func `the sort order is written by name`() throws {
        let orders = try Library.SortOrder.allCases.map { order in
            var state = AppState()
            state.sortOrder = order
            return try Self.json(state)["sortOrder"] as? String
        }

        #expect(orders == ["newestFirst", "oldestFirst", "name"])
    }

    @Test func `a playlist's default interval is half an hour`() {
        #expect(Playlist.defaultInterval == .seconds(30 * 60))
    }

    // MARK: Same state, same bytes

    @Test func `writes displays in a fixed order, so the same state gives the same bytes`() throws {
        let order = [5, 2, 8, 1, 7, 3, 6, 4]
        var state = AppState()
        for number in order {
            state.assignments[.numbered(number)] = .wallpaper(.numbered(number))
            state.rotation[.numbered(number)] = RotationState(current: .numbered(number))
            state.pausedDisplays.insert(.numbered(number))
        }
        let sorted = (1...8).map { DisplayIdentity.numbered($0).description }

        let json = try Self.json(state)

        #expect((json["assignments"] as? [[String: Any]])?.map { $0["display"] as? String } == sorted)
        #expect((json["rotation"] as? [[String: Any]])?.map { $0["display"] as? String } == sorted)
        #expect(json["pausedDisplays"] as? [String] == sorted)
    }

    @Test func `the same state built in another order gives the same bytes`() throws {
        var forwards = AppState()
        var backwards = AppState()
        for number in 1...8 {
            forwards.assignments[.numbered(number)] = .playlist(.numbered(number))
            forwards.pausedDisplays.insert(.numbered(number))
        }
        for number in (1...8).reversed() {
            backwards.assignments[.numbered(number)] = .playlist(.numbered(number))
            backwards.pausedDisplays.insert(.numbered(number))
        }

        #expect(try forwards.encode() == backwards.encode())
    }

    // MARK: Migration

    @Test func `the version 1.0 fixture still decodes`() throws {
        let decoded = try AppState.decode(Fixture.data("app-state-v1.0"))

        #expect(decoded == Self.fixtureState)
    }

    @Test func `a newer minor version decodes, and its new fields are ignored`() throws {
        let decoded = try AppState.decode(Fixture.data("app-state-v1.9-newer-minor"))

        var expected = AppState()
        // Its hotkeys have been known since version 1.1; its `openAtLogin` is still new.
        expected.hotkeys = [.nextWallpaper: KeyCombination(keyCode: 45, modifiers: [.control, .command], keyLabel: "N")]
        expected.assignments = [.numbered(1): .wallpaper(.numbered(1))]
        expected.playlists = [
            Playlist(id: .numbered(1), name: "Evening", wallpapers: [.numbered(1)], interval: .seconds(600), shuffle: false),
        ]
        expected.rotation = [.numbered(1): RotationState(current: .numbered(1), position: 0)]
        expected.isMuted = true
        #expect(decoded == expected)
    }

    static let failsClosed: [Row<String, SchemaError?>] = [
        Row(
            "an unknown major version",
            #"{"version":{"major":2,"minor":0},"assignments":[],"playlists":[],"rotation":[],"pauseRules":{},"pausedDisplays":[]}"#,
            .unsupportedVersion(SchemaVersion(major: 2, minor: 0))
        ),
        Row("no version at all", #"{"assignments":[],"playlists":[]}"#, nil),
        Row("a file cut short", #"{"version":{"major":1,"minor":0},"assignm"#, nil),
        Row("an empty file", "", nil),
        Row(
            "a display listed twice",
            appStateJSON(assignments: """
                {"display":"DDDDDDDD-0000-0000-0000-000000000001","assignment":{"wallpaper":"AAAAAAAA-0000-0000-0000-000000000001"}},
                {"display":"DDDDDDDD-0000-0000-0000-000000000001","assignment":{"wallpaper":"AAAAAAAA-0000-0000-0000-000000000002"}}
                """),
            nil
        ),
        Row(
            "an assignment that names nothing",
            appStateJSON(assignments: #"{"display":"DDDDDDDD-0000-0000-0000-000000000001","assignment":{}}"#),
            nil
        ),
        Row(
            "an assignment that names a wallpaper and a playlist",
            appStateJSON(assignments: """
                {"display":"DDDDDDDD-0000-0000-0000-000000000001",
                 "assignment":{"wallpaper":"AAAAAAAA-0000-0000-0000-000000000001","playlist":"BBBBBBBB-0000-0000-0000-000000000001"}}
                """),
            nil
        ),
        Row(
            "two playlists that share an identifier",
            appStateJSON(playlists: """
                {"id":"BBBBBBBB-0000-0000-0000-000000000001","name":"A","wallpapers":[],"interval":60,"shuffle":false},
                {"id":"BBBBBBBB-0000-0000-0000-000000000001","name":"B","wallpapers":[],"interval":60,"shuffle":false}
                """),
            nil
        ),
        // A hand-edited interval: nothing to rotate by, or so large that a `Duration` of it would trap.
        Row("a playlist that rotates every 0 seconds", appStateJSON(playlists: playlistJSON(interval: "0")), nil),
        Row("a playlist that rotates every -60 seconds", appStateJSON(playlists: playlistJSON(interval: "-60")), nil),
        Row("a playlist that rotates less than once a year", appStateJSON(playlists: playlistJSON(interval: "31536001")), nil),
        Row("an interval too large for a duration", appStateJSON(playlists: playlistJSON(interval: "1e30")), nil),
        Row("an interval past any number", appStateJSON(playlists: playlistJSON(interval: "1e400")), nil),
    ]

    /// Playlist 1 with no wallpapers, rotating every `interval` seconds, as written in the file.
    static func playlistJSON(interval: String) -> String {
        #"{"id":"BBBBBBBB-0000-0000-0000-000000000001","name":"A","wallpapers":[],"interval":\#(interval),"shuffle":false}"#
    }

    @Test func `a playlist may rotate every second, or once a year`() throws {
        let playlists = [1, 31_536_000].enumerated().map { index, seconds in
            Self.playlistJSON(interval: "\(seconds)").replacingOccurrences(of: "000000000001", with: "00000000000\(index + 1)")
        }

        let decoded = try AppState.decode(Data(Self.appStateJSON(playlists: playlists.joined(separator: ",")).utf8))

        #expect(decoded.playlists.map(\.interval) == [.seconds(1), .seconds(31_536_000)])
    }

    /// A version 1.0 state with these pairs and playlists, and defaults for the rest.
    static func appStateJSON(assignments: String = "", playlists: String = "") -> String {
        """
        {"version":{"major":1,"minor":0},"assignments":[\(assignments)],"playlists":[\(playlists)],"rotation":[],
         "pauseRules":{"whenDesktopCovered":true,"whenDisplayAsleepOrLocked":true,"inLowPowerMode":true,"onBattery":false},
         "pausedDisplays":[],"isMuted":false,"sortOrder":"newestFirst","recents":[]}
        """
    }

    @Test func `the defaults, written by hand, decode`() throws {
        #expect(try AppState.decode(Data(Self.appStateJSON().utf8)) == AppState())
    }

    @Test(arguments: failsClosed)
    func `fails closed`(row: Row<String, SchemaError?>) {
        let data = Data(row.input.utf8)

        if let expected = row.expected {
            #expect(throws: expected) { try AppState.decode(data) }
        } else {
            #expect(throws: (any Error).self) { try AppState.decode(data) }
        }
    }
}
