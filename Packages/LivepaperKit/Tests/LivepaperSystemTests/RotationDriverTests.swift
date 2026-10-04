import Foundation
import LivepaperCore
import LivepaperSystem
import LivepaperTestSupport
import os
import Testing

/// Stands in for the app model: commits what the driver hands it, and tells the
/// driver of every change to the state, the displays and Pause All, its own included.
@MainActor
final class RotationModel {
    var state: AppState
    var connected: [DisplayIdentity]
    var isPausedAll = false
    private(set) var commits: [AppState] = []
    var driver: RotationDriver?

    init(state: AppState, connected: [DisplayIdentity]) {
        self.state = state
        self.connected = connected
    }

    func commit(_ next: AppState) {
        commits.append(next)
        change { $0.state = next }
    }

    /// A change the app makes: a pause, an assignment, a display plugged in or out, Pause All.
    func change(_ edit: (RotationModel) -> Void) {
        edit(self)
        driver?.update(state: state, connected: connected, isPausedAll: isPausedAll)
    }

    /// What the display shows now.
    func shown(on display: DisplayIdentity) -> WallpaperID? {
        state.rotation[display]?.current
    }
}

// Some tests wait for the driver to hear a wake; one that never comes fails the test instead of hanging the run.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct RotationDriverTests {
    static let first = DisplayIdentity.numbered(1)
    static let second = DisplayIdentity.numbered(2)

    nonisolated static func wallpaper(_ number: Int) -> WallpaperID {
        WallpaperID(uuid: UUID(uuidString: "AAAAAAAA-0000-0000-0000-00000000000\(number)") ?? UUID())
    }

    /// Wallpapers 1 to 3 in order, every 10 minutes.
    static let evening = Playlist(
        id: PlaylistID(uuid: UUID(uuidString: "BBBBBBBB-0000-0000-0000-000000000001") ?? UUID()),
        name: "Evening", wallpapers: (1...3).map(wallpaper), interval: .seconds(600), shuffle: false
    )

    /// The first display on Evening, showing wallpaper 1 since `lastRotation` seconds after launch.
    static func state(lastRotation: TimeInterval = -100) -> AppState {
        var state = AppState()
        state.playlists = [evening]
        state.assignments[first] = .playlist(evening.id)
        state.rotation[first] = RotationState(current: wallpaper(1), position: 0, lastRotation: Moment.after(lastRotation))
        return state
    }

    let clock = ManualWallClock()
    let sleep = FakeSleepSensor()

    func driver(for model: RotationModel) -> RotationDriver {
        let driver = RotationDriver(
            clock: clock, sleep: sleep, rng: SeededGenerator(seed: 1),
            logger: Logger(subsystem: "app.livepaper.tests", category: RotationLog.category)
        ) { [weak model] next in model?.commit(next) }
        model.driver = driver
        return driver
    }

    /// Launches a driver for `model` at the clock's time, in a session that started `sessionStart` seconds after launch.
    @discardableResult
    func launch(_ model: RotationModel, sessionStart: TimeInterval? = -3600) -> RotationDriver {
        let driver = driver(for: model)
        driver.launch(
            state: model.state, connected: model.connected, isPausedAll: model.isPausedAll, sessionStart: sessionStart.map(Moment.after)
        )
        return driver
    }

    /// Lets the driver's own tasks run until `condition` holds, or gives up.
    func settle(until condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
    }

    // MARK: The timer

    @Test func `launching sets the timer for the end of the interval the loaded state began`() {
        let model = RotationModel(state: Self.state(lastRotation: -100), connected: [Self.first])

        let driver = launch(model)

        #expect(model.commits.isEmpty)
        #expect(driver.nextTick == Moment.after(500))
        #expect(clock.scheduled == [Moment.after(500)])
    }

    @Test func `the timer rotates at the end of the interval, not before, and is set again for the next`() {
        let model = RotationModel(state: Self.state(lastRotation: -100), connected: [Self.first])
        launch(model)

        clock.advance(toSecond: 499)
        let before = model.commits.count
        clock.advance(toSecond: 500)

        #expect(before == 0)
        #expect(model.commits.count == 1)
        #expect(model.shown(on: Self.first) == Self.wallpaper(2))
        #expect(model.state.rotation[Self.first]?.lastRotation == Moment.after(500))
        #expect(clock.scheduled == [Moment.after(1100)])
    }

    @Test func `a relaunch carries on the pass where it was`() {
        let model = RotationModel(state: Self.state(lastRotation: -100), connected: [Self.first])
        let first = launch(model)
        clock.advance(toSecond: 500)
        first.stop()

        clock.advance(toSecond: 700)
        let relaunched = RotationModel(state: model.state, connected: [Self.first])
        let second = launch(relaunched)

        #expect(relaunched.commits.isEmpty)
        #expect(second.nextTick == Moment.after(1100))
        #expect(clock.scheduled == [Moment.after(1100)])
    }

    @Test func `a display plugged out takes its interval out of the timer, and plugged back in puts it back`() {
        let model = RotationModel(state: Self.state(lastRotation: -100), connected: [Self.first])
        let driver = launch(model)

        model.change { $0.connected = [Self.second] }
        let unplugged = clock.scheduled
        model.change { $0.connected = [Self.first, Self.second] }

        #expect(unplugged.isEmpty)
        #expect(driver.nextTick == Moment.after(500))
        #expect(clock.scheduled == [Moment.after(500)])
    }

    @Test func `a new assignment sets the timer from when it started`() {
        let model = RotationModel(state: Self.state(lastRotation: -100), connected: [Self.first])
        let driver = launch(model)
        clock.advance(toSecond: 60)

        var rng = SeededGenerator(seed: 1)
        model.change { $0.state = $0.state.assigning(.playlist(Self.evening.id), to: [Self.second], now: Moment.after(60), rng: &rng) }
        model.change { $0.connected = [Self.second] }

        #expect(driver.nextTick == Moment.after(660))
    }

    // MARK: Wake and login

    @Test func `a wake rotates every display rotation moves`() async {
        let model = RotationModel(state: Self.state(lastRotation: -100), connected: [Self.first])
        let driver = launch(model)
        clock.advance(toSecond: 60)

        sleep.send(.willSleep)
        sleep.send(.didWake)
        await settle { model.commits.count == 1 }

        #expect(model.commits.count == 1)
        #expect(model.shown(on: Self.first) == Self.wallpaper(2))
        #expect(driver.nextTick == Moment.after(660))
    }

    @Test func `a timer that fell due in the sleep and fired at the wake is not followed by a second rotation`() async {
        let model = RotationModel(state: Self.state(lastRotation: -100), connected: [Self.first])
        launch(model)

        clock.sleep(untilSecond: 3600)
        sleep.send(.didWake)
        await Task.yield()
        await settle { false }

        #expect(model.commits.count == 1)
        #expect(model.shown(on: Self.first) == Self.wallpaper(2))
    }

    @Test func `the login rotates once a session, and a relaunch in the same session does not`() {
        let model = RotationModel(state: Self.state(lastRotation: -7200), connected: [Self.first])
        launch(model, sessionStart: -60)
        let atLogin = model.commits.count
        let shownAtLogin = model.shown(on: Self.first)

        clock.advance(toSecond: 30)
        let relaunched = RotationModel(state: model.state, connected: [Self.first])
        let driver = launch(relaunched, sessionStart: -60)

        #expect(atLogin == 1 && shownAtLogin == Self.wallpaper(2))
        #expect(relaunched.commits.isEmpty)
        #expect(driver.nextTick == Moment.after(600))
    }

    @Test func `with no session start known, the launch rotates nothing`() {
        let model = RotationModel(state: Self.state(lastRotation: -7200), connected: [Self.first])

        let driver = launch(model, sessionStart: nil)

        #expect(model.commits.isEmpty)
        #expect(driver.nextTick == Moment.after(-6600))
    }

    // MARK: Pause

    @Test func `a pause drops the ticks, and the display counts its interval from the resume`() {
        let model = RotationModel(state: Self.state(lastRotation: -100), connected: [Self.first])
        let driver = launch(model)

        model.change { $0.state = $0.state.settingPaused(true, for: Self.first) }
        let whilePaused = clock.scheduled
        clock.advance(toSecond: 1300)
        let ticked = model.commits.count
        model.change { $0.state = $0.state.settingPaused(false, for: Self.first) }

        #expect(whilePaused.isEmpty && ticked == 0)
        #expect(model.commits.count == 1)
        #expect(model.shown(on: Self.first) == Self.wallpaper(1))
        #expect(model.state.rotation[Self.first]?.lastRotation == Moment.after(1300))
        #expect(driver.nextTick == Moment.after(1900))
    }

    @Test func `under Pause All no tick or wake rotates, and every display counts from Resume All`() async {
        let model = RotationModel(state: Self.state(lastRotation: -100), connected: [Self.first])
        let driver = launch(model)

        model.change { $0.isPausedAll = true }
        clock.advance(toSecond: 1300)
        sleep.send(.didWake)
        await settle { false }
        let whilePaused = model.commits.count
        model.change { $0.isPausedAll = false }

        #expect(whilePaused == 0)
        #expect(model.state.rotation[Self.first]?.lastRotation == Moment.after(1300))
        #expect(driver.nextTick == Moment.after(1900))
    }

    @Test func `a Next on a paused display leaves it paused, and no timer is set until the resume`() throws {
        let model = RotationModel(state: Self.state(lastRotation: -100).settingPaused(true, for: Self.first), connected: [Self.first])
        let driver = launch(model)
        var rng = SeededGenerator(seed: 1)

        model.change { $0.state = $0.state.rotating(Self.first, .next(at: Moment.after(30)), rng: &rng) }

        #expect(model.shown(on: Self.first) == Self.wallpaper(2))
        #expect(model.state.pausedDisplays == [Self.first])
        #expect(driver.nextTick == nil && clock.scheduled.isEmpty)
    }

    // MARK: Before launch and after stop

    @Test func `before the launch nothing is set, and after a stop nothing rotates`() async {
        let model = RotationModel(state: Self.state(lastRotation: -100), connected: [Self.first])
        let driver = driver(for: model)

        driver.update(state: model.state, connected: model.connected, isPausedAll: false)
        let beforeLaunch = clock.scheduled
        driver.launch(state: model.state, connected: model.connected, isPausedAll: false, sessionStart: nil)
        driver.stop()
        clock.advance(toSecond: 3600)
        sleep.send(.didWake)
        await settle { false }

        #expect(beforeLaunch.isEmpty)
        #expect(clock.scheduled.isEmpty && driver.nextTick == nil)
        #expect(model.commits.isEmpty)
    }
}

/// The rotation check reads these lines, so their wording is pinned.
struct RotationLogTests {
    static let first = DisplayIdentity.numbered(1)
    static let second = DisplayIdentity.numbered(2)

    static let lines: [Row<String, String>] = [
        Row(
            "the login, with what it rotated",
            RotationLog.login(sessionStart: Moment.launch, rotated: [first, second]),
            "rotation: session started 2026-09-21T14:13:20Z, login rotated DDDDDDDD-0000-0000-0000-000000000001, "
                + "DDDDDDDD-0000-0000-0000-000000000002"
        ),
        Row("a login that rotated nothing", RotationLog.login(sessionStart: Moment.launch, rotated: []),
            "rotation: session started 2026-09-21T14:13:20Z, login rotated nothing"),
        Row("a tick", RotationLog.rotated(.tick, [first]), "rotation: tick rotated DDDDDDDD-0000-0000-0000-000000000001"),
        Row("a wake that rotated nothing", RotationLog.rotated(.wake, []), "rotation: wake rotated nothing"),
        Row(
            "counting from a resume",
            RotationLog.counting([first], from: Moment.launch),
            "rotation: DDDDDDDD-0000-0000-0000-000000000001 counts from 2026-09-21T14:13:20Z"
        ),
        Row("the timer", RotationLog.nextTick(Moment.after(600)), "rotation: next tick at 2026-09-21T14:23:20Z"),
        Row("no timer", RotationLog.nextTick(nil), "rotation: no tick due"),
    ]

    @Test(arguments: lines)
    func `each line is worded as the checks read it`(row: Row<String, String>) {
        #expect(row.input == row.expected)
    }
}
