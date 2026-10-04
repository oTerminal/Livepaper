import Foundation
import Testing
import LivepaperCore

struct RenderStateTests {
    static func display(_ number: Int, userPaused: Bool = false) -> RenderState.Display {
        RenderState.Display(
            identity: .numbered(number),
            wallpaper: .numbered(number),
            optimisedCopy: .known("wallpapers/\(WallpaperID.numbered(number))/wallpaper.mov"),
            poster: .known("wallpapers/\(WallpaperID.numbered(number))/poster.heic"),
            presentation: Presentation(),
            volume: 0,
            userPaused: userPaused
        )
    }

    /// What `render-state-v1.0.json` says.
    static var fixtureState: RenderState {
        var first = display(1, userPaused: true)
        first.presentation = Presentation(fit: .fill, focalPoint: Point(x: 0.25, y: 0.5), zoom: 1.5, pan: Point(x: 0.1, y: -0.2))
        first.volume = 0.4
        var second = display(2)
        second.presentation = Presentation(fit: .fit)
        return RenderState(
            generation: 42,
            displays: [first, second],
            pauseRules: PauseRules(whenDesktopCovered: true, whenDisplayAsleepOrLocked: true, inLowPowerMode: false, onBattery: true),
            conditions: SensedConditions(
                sensedAt: Date(timeIntervalSince1970: 1_789_984_800.25),
                coveredDisplays: [.numbered(2)],
                lowPowerMode: true
            )
        )
    }

    // MARK: Round trip

    static let roundTrips: [Row<RenderState, Void>] = [
        Row("two displays, rules and conditions", fixtureState, ()),
        Row("no displays and nothing sensed", RenderState(generation: 1, displays: [], pauseRules: PauseRules(), conditions: nil), ()),
        Row(
            "the stopped form keeps its displays, so the extension knows which poster to hold",
            RenderState(generation: 7, isStopped: true, displays: [display(1)], pauseRules: PauseRules(), conditions: nil),
            ()
        ),
        Row(
            "conditions sensed by the real clock, with all its digits",
            RenderState(
                generation: 1, displays: [], pauseRules: PauseRules(),
                conditions: SensedConditions(sensedAt: Date(timeIntervalSinceReferenceDate: 811_677_600.123_456_7))
            ),
            ()
        ),
        Row(
            "a generation beyond 32 bits",
            RenderState(generation: 5_000_000_000, displays: [display(1)], pauseRules: PauseRules(), conditions: nil),
            ()
        ),
        Row(
            "a scene on one display and a video on the other",
            RenderState(generation: 3, displays: [display(1), sceneDisplay(2, showing: 3)], pauseRules: PauseRules(), conditions: nil),
            ()
        ),
    ]

    /// Display `number` showing scene `wallpaper`, as `render-state-v1.1.json` has it.
    static func sceneDisplay(_ number: Int, showing wallpaper: Int) -> RenderState.Display {
        let folder = "wallpapers/\(WallpaperID.numbered(wallpaper))"
        var display = RenderState.Display(
            identity: .numbered(number),
            wallpaper: .numbered(wallpaper),
            optimisedCopy: .known("\(folder)/scene.pkg"),
            poster: .known("\(folder)/poster.heic"),
            presentation: Presentation(fit: .fit),
            volume: 0,
            userPaused: false
        )
        display.scene = WallpaperScene(project: .known("\(folder)/project.json"), width: 3840, height: 2160)
        return display
    }

    @Test(arguments: roundTrips)
    func `survives a round trip`(row: Row<RenderState, Void>) throws {
        let decoded = try RenderState.decode(row.input.encode())

        #expect(decoded == row.input)
    }

    @Test func `writes sets in a fixed order, so the same state gives the same bytes`() throws {
        var state = Self.fixtureState
        state.conditions?.coveredDisplays = Set([5, 2, 8, 1, 7, 3, 6, 4].map(DisplayIdentity.numbered))

        let json = try #require(JSONSerialization.jsonObject(with: state.encode()) as? [String: Any])
        let conditions = try #require(json["conditions"] as? [String: Any])

        #expect(conditions["coveredDisplays"] as? [String] == (1...8).map { DisplayIdentity.numbered($0).description })
    }

    @Test func `writes its schema version`() throws {
        let json = try #require(JSONSerialization.jsonObject(with: Self.fixtureState.encode()) as? [String: Any])

        #expect(json["version"] as? [String: Int] == ["major": 1, "minor": 1])
    }

    @Test func `a video's display is written as it was before scenes, with no scene field`() throws {
        let json = try #require(JSONSerialization.jsonObject(with: Self.fixtureState.encode()) as? [String: Any])
        let displays = try #require(json["displays"] as? [[String: Any]])

        #expect(displays.allSatisfy { $0["scene"] == nil })
    }

    // MARK: Migration

    @Test func `the version 1.0 fixture still decodes`() throws {
        let decoded = try RenderState.decode(Fixture.data("render-state-v1.0"))

        #expect(decoded == Self.fixtureState)
    }

    @Test func `the version 1.1 fixture decodes, with its scene`() throws {
        let decoded = try RenderState.decode(Fixture.data("render-state-v1.1"))

        var video = Self.display(1)
        video.presentation = Presentation()
        #expect(decoded == RenderState(
            generation: 44,
            displays: [video, Self.sceneDisplay(2, showing: 3)],
            pauseRules: PauseRules(whenDesktopCovered: true, whenDisplayAsleepOrLocked: true, inLowPowerMode: true, onBattery: false),
            conditions: nil
        ))
    }

    @Test func `a newer minor version decodes, and its new fields are ignored`() throws {
        let decoded = try RenderState.decode(Fixture.data("render-state-v1.9-newer-minor"))

        #expect(decoded == RenderState(generation: 43, displays: [Self.display(1)], pauseRules: PauseRules(), conditions: nil))
    }

    static let failsClosed: [Row<String, SchemaError?>] = [
        Row(
            "an unknown major version",
            #"{"version":{"major":2,"minor":0},"generation":1,"stopped":false,"displays":[],"pauseRules":{}}"#,
            .unsupportedVersion(SchemaVersion(major: 2, minor: 0))
        ),
        Row(
            "major version 0, which never existed",
            #"{"version":{"major":0,"minor":3},"generation":1,"stopped":false,"displays":[],"pauseRules":{}}"#,
            .unsupportedVersion(SchemaVersion(major: 0, minor: 3))
        ),
        Row("no version at all", #"{"generation":1,"stopped":false,"displays":[]}"#, nil),
        Row("a file cut short", #"{"version":{"major":1,"minor":0},"generation":1,"stop"#, nil),
        Row("an empty file", "", nil),
    ]

    @Test func `a state that names a file outside the library does not decode`() throws {
        let json = try #require(String(bytes: try Self.fixtureState.encode(), encoding: .utf8))
            .replacing("wallpapers/\(WallpaperID.numbered(2))/wallpaper.mov", with: "/etc/passwd")
        #expect(json.contains("/etc/passwd"))

        #expect(throws: LibraryPathError.absolute) { try RenderState.decode(Data(json.utf8)) }
    }

    /// The extension keeps what it shows when the state cannot be read.
    @Test(arguments: failsClosed)
    func `fails closed`(row: Row<String, SchemaError?>) {
        let data = Data(row.input.utf8)

        if let expected = row.expected {
            #expect(throws: expected) { try RenderState.decode(data) }
        } else {
            #expect(throws: (any Error).self) { try RenderState.decode(data) }
        }
    }

    // MARK: Generation

    @Test func `the generation only increases`() {
        let state = Self.fixtureState

        let paused = state.next { $0.displays[1].userPaused = true }
        let stopped = paused.next { $0.isStopped = true }
        let unchanged = stopped.next { _ in }

        #expect(paused.displays[1].userPaused)
        #expect([state, paused, stopped, unchanged].map(\.generation) == [42, 43, 44, 45])
    }

    // MARK: Conditions for the policy

    @Test func `gives the policy one display's conditions`() {
        let state = Self.fixtureState
        let now = Date(timeIntervalSince1970: 1_789_984_805)

        let first = state.playbackConditions(for: .numbered(1), now: now)
        let second = state.playbackConditions(for: .numbered(2), now: now)

        #expect(first == PlaybackConditions(
            userPaused: true, lowPowerMode: true, sensedAt: Date(timeIntervalSince1970: 1_789_984_800.25), now: now
        ))
        #expect(second == PlaybackConditions(
            desktopCovered: true, lowPowerMode: true, sensedAt: Date(timeIntervalSince1970: 1_789_984_800.25), now: now
        ))
    }

    @Test func `with nothing sensed, only user pause reaches the policy`() {
        let state = RenderState(generation: 1, displays: [Self.display(1, userPaused: true)], pauseRules: PauseRules(), conditions: nil)
        let host = HostCapabilities(showsLockScreen: true)

        let paused = state.playbackConditions(for: .numbered(1), now: Moment.launch)
        let unknown = state.playbackConditions(for: .numbered(9), now: Moment.launch)

        #expect(decidePlayback(paused, rules: state.pauseRules, host: host) == .pause(.user))
        #expect(decidePlayback(unknown, rules: state.pauseRules, host: host) == .play)
    }
}
