import Foundation
import Testing
import LivepaperCore

/// What version 1.1 adds: the hotkeys, and the login item's intent with the copy of Livepaper that asked.
struct AppStateLoginAndHotkeysTests {
    static let controlOptionP = KeyCombination(keyCode: 35, modifiers: [.control, .option], keyLabel: "P")
    static let controlOptionN = KeyCombination(keyCode: 45, modifiers: [.control, .option], keyLabel: "N")
    static let applications = LoginItemReconcileTests.applications

    /// What `app-state-v1.1.json` says: version 1.0's state, two hotkeys, and the login item asked on.
    static var fixtureState: AppState {
        var state = AppStateTests.fixtureState
        state.hotkeys = [.nextWallpaper: controlOptionN, .pauseOrResumeAll: controlOptionP]
        state.loginItemIntent = LoginItemIntent(openAtLogin: true, bundle: applications)
        return state
    }

    @Test func `a first launch has no hotkeys, and has not asked about the login item`() {
        #expect(AppState().hotkeys.isEmpty)
        #expect(AppState().loginItemIntent == nil)
    }

    // MARK: Files

    @Test func `the version 1.1 fixture decodes`() throws {
        #expect(try AppState.decode(Fixture.data("app-state-v1.1")) == Self.fixtureState)
    }

    @Test func `the version 1.0 fixture decodes with no hotkeys, and nothing asked`() throws {
        let decoded = try AppState.decode(Fixture.data("app-state-v1.0"))

        #expect(decoded.hotkeys.isEmpty)
        #expect(decoded.loginItemIntent == nil)
    }

    static let roundTrips: [Row<AppState, Void>] = [
        Row("two hotkeys and the login item asked on", fixtureState, ()),
        Row(
            "every action, one with every modifier, and the login item asked off by a copy with no signature",
            {
                var state = AppState()
                state.hotkeys = [
                    .pauseOrResumeAll: controlOptionP,
                    .nextWallpaper: controlOptionN,
                    .mute: KeyCombination(keyCode: 46, modifiers: [.control, .option, .shift, .command], keyLabel: "M"),
                    .openLibrary: KeyCombination(keyCode: 105, modifiers: [], keyLabel: "F13"),
                ]
                state.loginItemIntent = LoginItemIntent(
                    openAtLogin: false, bundle: BundleIdentity(path: "/Users/someone/Desktop/Livepaper.app", designatedRequirement: nil)
                )
                return state
            }(),
            ()
        ),
    ]

    @Test(arguments: roundTrips)
    func `survives a round trip`(row: Row<AppState, Void>) throws {
        #expect(try AppState.decode(row.input.encode()) == row.input)
    }

    // MARK: Shapes

    @Test func `writes version 1.1`() throws {
        #expect(AppState.schemaVersion == SchemaVersion(major: 1, minor: 1))
        #expect(try AppStateTests.json(AppState())["version"] as? [String: Int] == ["major": 1, "minor": 1])
    }

    @Test func `a hotkey is written flat, its action beside the key, in the actions' order`() throws {
        var state = AppState()
        state.hotkeys = [.openLibrary: Self.controlOptionN, .pauseOrResumeAll: Self.controlOptionP]

        let hotkeys = try #require(AppStateTests.json(state)["hotkeys"] as? [[String: Any]])

        #expect(hotkeys.map { $0["action"] as? String } == ["pauseOrResumeAll", "openLibrary"])
        #expect(hotkeys.map { $0["keyCode"] as? Int } == [35, 45])
        #expect(hotkeys.map { $0["modifiers"] as? Int } == [3, 3])
        #expect(hotkeys.map { $0["keyLabel"] as? String } == ["P", "N"])
        #expect(hotkeys.map { $0.count } == [4, 4])
    }

    @Test func `the same hotkeys assigned in another order give the same bytes`() throws {
        var forwards = AppState()
        var backwards = AppState()
        for action in HotkeyAction.allCases {
            forwards.hotkeys[action] = KeyCombination(keyCode: 96, modifiers: .command, keyLabel: action.rawValue)
        }
        for action in HotkeyAction.allCases.reversed() {
            backwards.hotkeys[action] = KeyCombination(keyCode: 96, modifiers: .command, keyLabel: action.rawValue)
        }

        #expect(try forwards.encode() == backwards.encode())
    }

    @Test func `the login item's intent is written with the path and requirement of the copy that asked`() throws {
        let intent = try #require(AppStateTests.json(Self.fixtureState)["loginItemIntent"] as? [String: Any])

        #expect(intent["openAtLogin"] as? Bool == true)
        #expect(intent["bundle"] as? [String: String] == [
            "path": "/Applications/Livepaper.app", "designatedRequirement": LoginItemReconcileTests.requirement,
        ])
    }

    @Test func `nothing asked is written as no key, and no hotkeys as none`() throws {
        let json = try AppStateTests.json(AppState())

        #expect(json["loginItemIntent"] == nil)
        #expect((json["hotkeys"] as? [Any])?.isEmpty == true)
    }

    // MARK: Newer and damaged files

    @Test func `an action a newer version added is passed over, as its other new fields are`() throws {
        let json = Self.appStateJSON(hotkeys: """
            {"action":"previousWallpaper","keyCode":123,"modifiers":3,"keyLabel":"←"},
            {"action":"mute","keyCode":46,"modifiers":3,"keyLabel":"M"}
            """)

        let decoded = try AppState.decode(Data(json.utf8))

        #expect(decoded.hotkeys == [.mute: KeyCombination(keyCode: 46, modifiers: [.control, .option], keyLabel: "M")])
    }

    @Test func `an action listed twice fails closed`() {
        let json = Self.appStateJSON(hotkeys: """
            {"action":"mute","keyCode":46,"modifiers":3,"keyLabel":"M"},
            {"action":"mute","keyCode":45,"modifiers":3,"keyLabel":"N"}
            """)

        #expect(throws: (any Error).self) { try AppState.decode(Data(json.utf8)) }
    }

    @Test func `an intent that names no copy fails closed`() {
        let json = Self.appStateJSON(loginItemIntent: #"{"openAtLogin":true}"#)

        #expect(throws: (any Error).self) { try AppState.decode(Data(json.utf8)) }
    }

    /// A version 1.1 state with these hotkeys and this intent, and defaults for the rest.
    static func appStateJSON(hotkeys: String = "", loginItemIntent: String? = nil) -> String {
        """
        {"version":{"major":1,"minor":1},"assignments":[],"playlists":[],"rotation":[],
         "pauseRules":{"whenDesktopCovered":true,"whenDisplayAsleepOrLocked":true,"inLowPowerMode":true,"onBattery":false},
         "pausedDisplays":[],"isMuted":false,"sortOrder":"newestFirst","recents":[],
         \(loginItemIntent.map { #""loginItemIntent":\#($0),"# } ?? "")"hotkeys":[\(hotkeys)]}
        """
    }
}
