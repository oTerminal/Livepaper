import Foundation
import LivepaperTestSupport
import Testing
import LivepaperCore

/// The rotation driver's decisions over the app state: which displays move,
/// when the next tick is due, and what a tick, a wake, the login and a resume do.
struct RotationScheduleTests {
    static let first = DisplayIdentity.numbered(1)
    static let second = DisplayIdentity.numbered(2)
    static let third = DisplayIdentity.numbered(3)

    /// Wallpapers 1 to 3, in order, every 10 minutes.
    static let evening = Playlist(
        id: .numbered(1), name: "Evening", wallpapers: (1...3).map(WallpaperID.numbered), interval: .seconds(600), shuffle: false
    )
    /// Wallpapers 4 and 5, in order, every 20 minutes.
    static let focus = Playlist(
        id: .numbered(2), name: "Focus", wallpapers: [.numbered(4), .numbered(5)], interval: .seconds(1200), shuffle: false
    )

    /// Each display on its own playlist, showing its first wallpaper since `lastRotation` seconds after launch.
    static func state(_ displays: [DisplayIdentity: (Playlist, TimeInterval?)]) -> AppState {
        var state = AppState()
        state.playlists = [evening, focus]
        for (display, (playlist, last)) in displays {
            state.assignments[display] = .playlist(playlist.id)
            state.rotation[display] = RotationState(
                current: playlist.wallpapers[0], position: 0, lastRotation: last.map(Moment.after)
            )
        }
        return state
    }

    /// The display shows wallpaper 9 of its own instead.
    static func showingWallpaper(_ state: AppState, on display: DisplayIdentity) -> AppState {
        var state = state
        state.assignments[display] = .wallpaper(.numbered(9))
        return state
    }

    static func schedule(_ state: AppState, connected: [DisplayIdentity] = [first, second], isPausedAll: Bool = false) -> RotationSchedule {
        RotationSchedule(state: state, connected: connected, isPausedAll: isPausedAll)
    }

    static func shown(on display: DisplayIdentity, in state: AppState) -> WallpaperID? {
        state.rotation[display]?.current
    }

    // MARK: The next tick

    struct Arming: Sendable {
        var state: AppState
        var connected: [DisplayIdentity] = [first, second]
        var isPausedAll = false
    }

    static let armings: [Row<Arming, TimeInterval?>] = [
        Row("one display: its last rotation and its interval", Arming(state: state([first: (evening, 0)])), 600),
        Row("the earliest of two", Arming(state: state([first: (evening, 900), second: (focus, 0)])), 1200),
        Row(
            "a paused display is left out",
            Arming(state: state([first: (evening, 0), second: (focus, 0)]).settingPaused(true, for: first)),
            1200
        ),
        Row("under Pause All, none", Arming(state: state([first: (evening, 0)]), isPausedAll: true), nil),
        Row("a display that is not connected is left out", Arming(state: state([first: (evening, 0)]), connected: [second]), nil),
        Row(
            "a display showing a wallpaper is left out",
            Arming(state: showingWallpaper(state([first: (evening, 0)]), on: first)),
            nil
        ),
        Row("nothing assigned, nothing due", Arming(state: AppState()), nil),
        Row("a playlist that ended long ago is due at once", Arming(state: state([first: (evening, -86400)])), -85800),
    ]

    @Test(arguments: armings)
    func `the next tick is the earliest end of an interval among the displays rotation moves`(row: Row<Arming, TimeInterval?>) {
        let schedule = Self.schedule(row.input.state, connected: row.input.connected, isPausedAll: row.input.isPausedAll)

        #expect(schedule.nextTick == row.expected.map(Moment.after))
    }

    @Test(arguments: [UInt64](0..<200))
    func `a tick at the moment the schedule gives always finds the interval passed`(seed: UInt64) throws {
        // Any time of day and any interval: a date plus an interval does not always come back as the same interval.
        var numbers = SeededGenerator(seed: seed)
        let last = Date(timeIntervalSinceReferenceDate: Double(numbers.next() % 1_000_000_000_000) / 1000)
        var playlist = Self.evening
        playlist.interval = .seconds(Double(numbers.next() % 100_000_000) / 1000 + 1)
        var state = Self.state([Self.first: (playlist, 0)])
        state.playlists = [playlist]
        state.rotation[Self.first]?.lastRotation = last
        var schedule = Self.schedule(state)
        var rng = SeededGenerator(seed: 1)

        let due = try #require(schedule.nextTick)
        let change = schedule.tick(at: due, rng: &rng)

        #expect(change?.rotated == [Self.first])
        #expect(change?.state.rotation[Self.first]?.lastRotation == due)
        #expect(Self.shown(on: Self.first, in: schedule.state) == .numbered(2))
    }

    // MARK: A tick

    @Test func `a tick rotates at the end of the interval, and not before`() throws {
        var schedule = Self.schedule(Self.state([Self.first: (Self.evening, 0)]))
        var rng = SeededGenerator(seed: 1)

        let early = schedule.tick(at: Moment.after(599), rng: &rng)
        let onTime = try #require(schedule.tick(at: Moment.after(600), rng: &rng))

        #expect(early == nil)
        #expect(onTime.rotated == [Self.first])
        #expect(Self.shown(on: Self.first, in: onTime.state) == .numbered(2))
        #expect(onTime.state.rotation[Self.first]?.lastRotation == Moment.after(600))
        #expect(schedule.state == onTime.state)
        #expect(schedule.nextTick == Moment.after(1200))
    }

    @Test func `a tick rotates only the displays that are due`() throws {
        var schedule = Self.schedule(Self.state([Self.first: (Self.evening, 0), Self.second: (Self.focus, 0)]))
        var rng = SeededGenerator(seed: 1)

        let change = try #require(schedule.tick(at: Moment.after(600), rng: &rng))

        #expect(change.rotated == [Self.first])
        #expect(Self.shown(on: Self.second, in: change.state) == .numbered(4))
        #expect(schedule.nextTick == Moment.after(1200))
    }

    @Test func `a tick long after the interval rotates once`() throws {
        var schedule = Self.schedule(Self.state([Self.first: (Self.evening, 0)]))
        var rng = SeededGenerator(seed: 1)

        let change = try #require(schedule.tick(at: Moment.after(9000), rng: &rng))

        #expect(Self.shown(on: Self.first, in: change.state) == .numbered(2))
        #expect(schedule.nextTick == Moment.after(9600))
    }

    // MARK: Wake

    @Test func `a wake rotates every display rotation moves, whatever their intervals`() throws {
        let state = Self.state([Self.first: (Self.evening, 0), Self.second: (Self.focus, 0), Self.third: (Self.evening, 0)])
        var schedule = Self.schedule(state.settingPaused(true, for: Self.third), connected: [Self.first, Self.second, Self.third])
        var rng = SeededGenerator(seed: 1)

        let change = try #require(schedule.wake(at: Moment.after(60), rng: &rng))

        #expect(change.rotated == [Self.first, Self.second])
        #expect(Self.shown(on: Self.first, in: change.state) == .numbered(2))
        #expect(Self.shown(on: Self.second, in: change.state) == .numbered(5))
        #expect(Self.shown(on: Self.third, in: change.state) == .numbered(1))
        #expect(schedule.nextTick == Moment.after(660))
    }

    @Test func `a timer that fell due in the sleep and fired at the wake is not followed by a second rotation`() throws {
        var schedule = Self.schedule(Self.state([Self.first: (Self.evening, 0), Self.second: (Self.focus, 0)]))
        var rng = SeededGenerator(seed: 1)

        let tick = try #require(schedule.tick(at: Moment.after(3600), rng: &rng))
        let wake = schedule.wake(at: Moment.after(3601), rng: &rng)
        let shown = Self.shown(on: Self.first, in: schedule.state)
        let nextWake = schedule.wake(at: Moment.after(3610), rng: &rng)

        #expect(tick.rotated == [Self.first, Self.second])
        #expect(wake == nil)
        #expect(shown == .numbered(2))
        #expect(nextWake?.rotated == [Self.first, Self.second])
    }

    @Test func `a wake with nothing to rotate changes nothing`() {
        var schedule = Self.schedule(Self.state([Self.first: (Self.evening, 0)]), isPausedAll: true)
        var rng = SeededGenerator(seed: 1)

        #expect(schedule.wake(at: Moment.after(60), rng: &rng) == nil)
    }

    // MARK: Login

    struct Login: Sendable {
        var lastRotation: TimeInterval
        var sessionStart: TimeInterval
        var paused = false
    }

    static let logins: [Row<Login, [DisplayIdentity]>] = [
        Row("the last rotation was before the session started: it rotates", Login(lastRotation: -600, sessionStart: -60), [first]),
        Row("a relaunch in the same session: it rotated after the start, so not again", Login(lastRotation: -30, sessionStart: -60), []),
        Row("a paused display does not", Login(lastRotation: -600, sessionStart: -60, paused: true), []),
    ]

    @Test(arguments: logins)
    func `the login rotates the displays that have not rotated since the session started`(row: Row<Login, [DisplayIdentity]>) {
        let state = Self.state([Self.first: (Self.evening, row.input.lastRotation)]).settingPaused(row.input.paused, for: Self.first)
        var schedule = Self.schedule(state)
        var rng = SeededGenerator(seed: 1)

        let change = schedule.login(sessionStart: Moment.after(row.input.sessionStart), at: Moment.launch, rng: &rng)

        #expect((change?.rotated ?? []) == row.expected)
    }

    @Test func `the login's rotation starts the interval, so a relaunch finds nothing to do`() throws {
        var schedule = Self.schedule(Self.state([Self.first: (Self.evening, -600)]))
        var rng = SeededGenerator(seed: 1)
        let change = try #require(schedule.login(sessionStart: Moment.after(-60), at: Moment.launch, rng: &rng))

        var relaunch = Self.schedule(change.state)
        let again = relaunch.login(sessionStart: Moment.after(-60), at: Moment.after(30), rng: &rng)

        #expect(Self.shown(on: Self.first, in: change.state) == .numbered(2))
        #expect(again == nil)
        #expect(relaunch.nextTick == Moment.after(600))
    }

}

// Pauses, Next and Previous, counting, and the version 1.0 file.
extension RotationScheduleTests {
    // MARK: Pause

    @Test func `a pause drops the ticks, and the display counts its interval from the resume`() throws {
        var schedule = Self.schedule(Self.state([Self.first: (Self.evening, 0)]).settingPaused(true, for: Self.first))
        var rng = SeededGenerator(seed: 1)

        let whilePaused = schedule.tick(at: Moment.after(1300), rng: &rng)
        let unpaused = schedule.state.settingPaused(false, for: Self.first)
        let resume = schedule.change(state: unpaused, connected: [Self.first], isPausedAll: false, at: Moment.after(1300))
        let resumed = try #require(resume)

        #expect(whilePaused == nil)
        #expect(resumed.rotated.isEmpty && resumed.counting == [Self.first])
        #expect(resumed.state.rotation[Self.first]?.lastRotation == Moment.after(1300))
        #expect(Self.shown(on: Self.first, in: resumed.state) == .numbered(1))
        #expect(schedule.nextTick == Moment.after(1900))
    }

    @Test func `under Pause All no display ticks, and each counts from Resume All`() throws {
        let state = Self.state([Self.first: (Self.evening, 0), Self.second: (Self.focus, 0)])
        var schedule = Self.schedule(state)
        var rng = SeededGenerator(seed: 1)

        let paused = schedule.change(state: state, connected: [Self.first, Self.second], isPausedAll: true, at: Moment.after(10))
        let whilePaused = schedule.tick(at: Moment.after(2500), rng: &rng)
        let wake = schedule.wake(at: Moment.after(2500), rng: &rng)
        let resume = schedule.change(state: state, connected: [Self.first, Self.second], isPausedAll: false, at: Moment.after(3000))
        let resumed = try #require(resume)

        #expect(paused == nil && whilePaused == nil && wake == nil)
        #expect(resumed.counting == [Self.first, Self.second])
        #expect(schedule.nextTick == Moment.after(3600))
    }

    @Test func `pause rules do not hold rotation`() throws {
        var state = Self.state([Self.first: (Self.evening, 0)])
        state.pauseRules = PauseRules(whenDesktopCovered: true, whenDisplayAsleepOrLocked: true, inLowPowerMode: true, onBattery: true)
        var schedule = Self.schedule(state)
        var rng = SeededGenerator(seed: 1)

        #expect(try #require(schedule.tick(at: Moment.after(600), rng: &rng)).rotated == [Self.first])
    }

    @Test func `on a paused display Next works and leaves it paused, and the next tick waits for the resume`() throws {
        let library = try Library.of(contentsOf: (1...3).map { Wallpaper.numbered($0) })
        let paused = Self.state([Self.first: (Self.evening, 0)]).settingPaused(true, for: Self.first)
        var schedule = Self.schedule(paused, connected: [Self.first])
        var histories = RotationHistories()
        var rng = SeededGenerator(seed: 1)

        let afterNext = histories.next(on: Self.first, in: paused, library: library, now: Moment.after(100), rng: &rng)
        let change = schedule.change(state: afterNext, connected: [Self.first], isPausedAll: false, at: Moment.after(100))

        #expect(afterNext.wallpaper(shownOn: Self.first, in: library)?.id == .numbered(2))
        #expect(afterNext.pausedDisplays == [Self.first])
        #expect(change == nil)
        #expect(schedule.nextTick == nil)
        let back = histories.previous(on: Self.first, in: afterNext, library: library)
        #expect(back.wallpaper(shownOn: Self.first, in: library)?.id == .numbered(1))
    }

    @Test func `after a tick, Previous steps back to what the tick moved away from`() throws {
        let library = try Library.of(contentsOf: (1...5).map { Wallpaper.numbered($0) })
        var shuffled = Self.evening
        shuffled.wallpapers = (1...5).map(WallpaperID.numbered)
        shuffled.shuffle = true
        var state = Self.state([Self.first: (shuffled, 0)])
        state.playlists = [shuffled]
        state.rotation[Self.first] = RotationState(current: .numbered(3), position: 2, lastRotation: Moment.launch)
        var schedule = Self.schedule(state, connected: [Self.first])
        var histories = RotationHistories()
        var rng = SeededGenerator(seed: 42)

        let tick = try #require(schedule.tick(at: Moment.after(600), rng: &rng))
        histories.rotated(from: state, to: tick.state, library: library)
        let back = histories.previous(on: Self.first, in: tick.state, library: library)

        // The pass pinned in RotationTests starts with 2, and the playlist's own order has 1 before it.
        #expect(tick.state.wallpaper(shownOn: Self.first, in: library)?.id == .numbered(2))
        #expect(back.wallpaper(shownOn: Self.first, in: library)?.id == .numbered(3))
    }

    @Test func `counting from a resume leaves Previous as it was`() throws {
        let library = try Library.of(contentsOf: (1...3).map { Wallpaper.numbered($0) })
        let paused = Self.state([Self.first: (Self.evening, 0)]).settingPaused(true, for: Self.first)
        var schedule = Self.schedule(paused, connected: [Self.first])
        var histories = RotationHistories()

        let unpaused = paused.settingPaused(false, for: Self.first)
        let resume = schedule.change(state: unpaused, connected: [Self.first], isPausedAll: false, at: Moment.after(900))
        let resumed = try #require(resume)
        histories.rotated(from: paused, to: resumed.state, library: library)
        let back = histories.previous(on: Self.first, in: resumed.state, library: library)

        #expect(back.wallpaper(shownOn: Self.first, in: library)?.id == .numbered(3))
    }

    // MARK: Counting

    @Test func `a display showing a playlist with nothing on record counts from when it is first seen`() throws {
        // All Displays set while the second display was unplugged: it has no rotation of its own yet.
        var state = Self.state([Self.first: (Self.evening, 0)])
        state.applyToAll = .playlist(Self.focus.id)
        var schedule = Self.schedule(state, connected: [Self.first])

        let plugging = schedule.change(state: state, connected: [Self.first, Self.second], isPausedAll: false, at: Moment.after(50))
        let plugged = try #require(plugging)

        #expect(plugged.counting == [Self.second])
        #expect(plugged.state.rotation[Self.second] == RotationState(lastRotation: Moment.after(50)))
        #expect(schedule.nextTick == Moment.after(600))
    }

    @Test func `a rotation on record later than now, the clock having gone back, counts from now`() throws {
        var schedule = Self.schedule(Self.state([Self.first: (Self.evening, 86400)]))

        let state = schedule.state
        let counted = schedule.change(state: state, connected: [Self.first, Self.second], isPausedAll: false, at: Moment.launch)
        let change = try #require(counted)

        #expect(change.counting == [Self.first])
        #expect(schedule.nextTick == Moment.after(600))
    }

    @Test func `a change that changes nothing answers nothing`() {
        let state = Self.state([Self.first: (Self.evening, 0)])
        var schedule = Self.schedule(state)

        #expect(schedule.change(state: state, connected: [Self.first, Self.second], isPausedAll: false, at: Moment.after(10)) == nil)
        #expect(schedule.nextTick == Moment.after(600))
    }

    @Test func `a new state, connection or Pause All moves the next tick`() {
        var schedule = Self.schedule(Self.state([Self.first: (Self.evening, 0)]))
        var rng = SeededGenerator(seed: 1)
        let focusToo = Self.state([Self.first: (Self.evening, 0)])
            .assigning(.playlist(Self.focus.id), to: [Self.first], now: Moment.after(30), rng: &rng)

        _ = schedule.change(state: focusToo, connected: [Self.first], isPausedAll: false, at: Moment.after(30))
        let reassigned = schedule.nextTick
        _ = schedule.change(state: focusToo, connected: [Self.second], isPausedAll: false, at: Moment.after(40))
        let unplugged = schedule.nextTick

        #expect(reassigned == Moment.after(1230))
        #expect(unplugged == nil)
    }

    // MARK: The version 1.0 file

    @Test func `a version 1.0 app state loads and drives rotation`() throws {
        let state = try AppState.decode(Fixture.data("app-state-v1.0"))
        let lastRotation = Date(timeIntervalSince1970: 1_789_984_800.25)
        var schedule = Self.schedule(state, connected: [Self.first, Self.second])
        var rng = SeededGenerator(seed: 1)

        let armed = schedule.nextTick
        let tick = try #require(schedule.tick(at: lastRotation.addingTimeInterval(1800), rng: &rng))
        var atLogin = Self.schedule(state, connected: [Self.first, Self.second])
        let login = try #require(atLogin.login(sessionStart: lastRotation.addingTimeInterval(60), at: Moment.launch, rng: &rng))

        // The first display is paused and shows a wallpaper; the second's shuffled pass has one left, wallpaper 1.
        #expect(armed == lastRotation.addingTimeInterval(1800))
        #expect(tick.rotated == [Self.second])
        #expect(Self.shown(on: Self.second, in: tick.state) == .numbered(1))
        #expect(login.rotated == [Self.second])
        #expect(Self.shown(on: Self.second, in: login.state) == .numbered(1))
    }
}
