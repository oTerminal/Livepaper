import Foundation
import Testing
import LivepaperCore
import LivepaperPlayback

struct RenderStateReaderTests {
    static let playing = RenderState(generation: 7, displays: [.numbered(1)], pauseRules: PauseRules(), conditions: nil)
    static let later = playing.next { $0.displays = [.numbered(1, showing: 2)] }
    static let stopped = playing.next { $0.isStopped = true }
    /// Pause All: every display paused by the user, as its own pause is.
    static let pausedAll = playing.next { $0.displays = [.numbered(1, userPaused: true)] }

    // MARK: What a read does to what is shown

    struct Arrival: Sendable {
        var current: CurrentRenderState
        var read: RenderStateRead
    }

    static let arrivals: [Row<Arrival, CurrentRenderState>] = [
        Row("no file shows nothing", Arrival(current: .none, read: .missing), .none),
        Row("a file that went away shows nothing", Arrival(current: .state(playing), read: .missing), .none),
        Row("an unreadable file keeps what is shown", Arrival(current: .state(playing), read: .unreadable("malformed")), .state(playing)),
        Row(
            "an unknown major version keeps what is shown",
            Arrival(current: .state(playing), read: .unreadable("unknown schema version 2.0")),
            .state(playing)
        ),
        Row("an unreadable file at launch leaves nothing shown", Arrival(current: .none, read: .unreadable("malformed")), .none),
        Row("a readable state applies", Arrival(current: .none, read: .read(playing)), .state(playing)),
        Row("a newer state replaces the one shown", Arrival(current: .state(playing), read: .read(later)), .state(later)),
        Row("the stopped state applies", Arrival(current: .state(playing), read: .read(stopped)), .state(stopped)),
    ]

    @Test(arguments: arrivals)
    func `a read changes what is shown`(row: Row<Arrival, CurrentRenderState>) {
        #expect(row.input.current.applying(row.input.read) == row.expected)
    }

    // MARK: What a display's surfaces are to show

    struct Question: Sendable {
        var current: CurrentRenderState
        var display: Int = 1
        var now = Moment.after(1)
    }

    static let covered = RenderState(
        displays: [.numbered(1), .numbered(2, userPaused: true)],
        pauseRules: PauseRules(),
        conditions: SensedConditions(sensedAt: Moment.launch, coveredDisplays: [.numbered(1)])
    )

    static let targets: [Row<Question, SurfaceTarget>] = [
        Row("no render state shows nothing", Question(current: .none), .nothing),
        Row("a display absent from the state shows nothing", Question(current: .state(playing), display: 3), .nothing),
        Row("the stopped state holds the display's poster", Question(current: .state(stopped)), .still(.numbered(1))),
        Row(
            "Pause All pauses the display in place, as its own pause does",
            Question(current: .state(pausedAll)),
            .playback(.numbered(1), .pause(.user))
        ),
        Row("a readable state plays the display's wallpaper", Question(current: .state(playing)), .playback(.numbered(1), .play)),
        Row("a covered display pauses by its rule", Question(current: .state(covered)), .playback(.numbered(1), .pause(.desktopCovered))),
        Row(
            "the user's pause is the display's own",
            Question(current: .state(covered), display: 2),
            .playback(.numbered(2), .pause(.user))
        ),
        Row(
            "conditions older than their expiry no longer pause",
            Question(current: .state(covered), now: Moment.after(31)),
            .playback(.numbered(1), .play)
        ),
    ]

    @Test(arguments: targets)
    func `decides what a display's surfaces show`(row: Row<Question, SurfaceTarget>) {
        let target = row.input.current.target(
            for: .numbered(row.input.display), location: testLibrary, host: HostCapabilities(showsLockScreen: true), now: row.input.now
        )

        #expect(target == row.expected)
    }

    static let stills: [Row<CurrentRenderState, Bool>] = [
        Row("no render state is holding still", .none, true),
        Row("the stopped state is holding still", .state(stopped), true),
        Row("a playing state is not", .state(playing), false),
        Row("Pause All's state is not: each display is paused, its decoder kept", .state(pausedAll), false),
    ]

    @Test(arguments: stills)
    func `tells the heartbeat whether it holds a still`(row: Row<CurrentRenderState, Bool>) {
        #expect(row.input.isHoldingStill == row.expected)
    }

    // MARK: Reading the file

    @Test func `no file is missing`() throws {
        let home = try TemporaryHome()

        #expect(RenderStateReader(location: home.location).read() == .missing)
    }

    @Test func `reads the version 1.0 fixture`() throws {
        let home = try TemporaryHome()
        try home.writeRenderState(Self.fixture())

        let read = RenderStateReader(location: home.location).read()

        guard case .read(let state) = read else {
            Issue.record("expected a state, read \(read)")
            return
        }
        #expect(state.generation == 42)
        #expect(!state.isStopped)
        #expect(state.displays.map(\.identity) == [.numbered(1), .numbered(2)])
        let sensedAt = try #require(state.conditions?.sensedAt)
        let target = CurrentRenderState.state(state).target(
            for: .numbered(2), location: home.location, host: HostCapabilities(showsLockScreen: true), now: sensedAt.addingTimeInterval(1)
        )
        let wallpaper = SurfaceWallpaper(state.displays[1], in: home.location)
        #expect(target == .playback(wallpaper, .pause(.desktopCovered)))
        #expect(wallpaper.video == home.location.root.appending(path: "wallpapers/AAAAAAAA-0000-0000-0000-000000000002/wallpaper.mov"))
    }

    @Test func `the stopped fixture holds the still`() throws {
        let home = try TemporaryHome()
        let fixture = try Self.fixture()
        try home.writeRenderState(try Self.replacing(#""stopped": false"#, with: #""stopped": true"#, in: fixture))

        let current = CurrentRenderState.none.applying(RenderStateReader(location: home.location).read())

        guard case .state(let state) = current else {
            Issue.record("expected a state, have \(current)")
            return
        }
        let target = current.target(
            for: .numbered(1), location: home.location, host: HostCapabilities(showsLockScreen: true), now: Moment.launch
        )
        #expect(target == .still(SurfaceWallpaper(state.displays[0], in: home.location)))
    }

    static let unreadable: [Row<String, Void>] = [
        Row("not JSON", "not json", ()),
        Row("an empty file", "", ()),
        Row("a major version this build does not know", #"{ "version": { "major": 2, "minor": 0 }, "generation": 43 }"#, ()),
    ]

    @Test(arguments: unreadable)
    func `a file it cannot trust is unreadable`(row: Row<String, Void>) throws {
        let home = try TemporaryHome()
        try home.writeRenderState(Data(row.input.utf8))

        let read = RenderStateReader(location: home.location).read()

        guard case .unreadable = read else {
            Issue.record("expected unreadable, read \(read)")
            return
        }
    }

    @Test func `a path that leaves the library is unreadable`() throws {
        let home = try TemporaryHome()
        let poster = #""wallpapers/AAAAAAAA-0000-0000-0000-000000000001/poster.heic""#
        try home.writeRenderState(try Self.replacing(poster, with: #""../../poster.heic""#, in: Self.fixture()))

        let read = RenderStateReader(location: home.location).read()

        guard case .unreadable = read else {
            Issue.record("expected unreadable, read \(read)")
            return
        }
    }

    @Test func `a file it may not open is unreadable`() throws {
        let home = try TemporaryHome()
        try home.writeRenderState(Self.fixture())
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: home.location.renderState.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: home.location.renderState.path) }

        let read = RenderStateReader(location: home.location).read()

        guard case .unreadable = read else {
            Issue.record("expected unreadable, read \(read)")
            return
        }
    }

    // MARK: Helpers

    /// LivepaperCoreTests' fixture, read where it is checked in.
    static func fixture() throws -> Data {
        let url = URL(filePath: #filePath)
            .deletingLastPathComponent()
            .appending(path: "../LivepaperCoreTests/Fixtures/render-state-v1.0.json")
        return try Data(contentsOf: url)
    }

    static func replacing(_ text: String, with replacement: String, in data: Data) throws -> Data {
        let json = try #require(String(bytes: data, encoding: .utf8))
        try #require(json.contains(text), "the fixture no longer says \(text)")
        return Data(json.replacingOccurrences(of: text, with: replacement).utf8)
    }
}

/// A home folder of the test's own, so that the reader finds the library where the extension would.
final class TemporaryHome: Sendable {
    let url: URL
    let location: LibraryLocation

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appending(path: "LivepaperPlaybackTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        location = LibraryLocation(home: url)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func writeRenderState(_ data: Data) throws {
        try FileManager.default.createDirectory(at: location.root, withIntermediateDirectories: true)
        try data.write(to: location.renderState)
    }
}
