import Foundation
import os
import Testing
import LivepaperCore
import LivepaperPlayback
import LivepaperTestSupport

/// The supervisor as the extension owns it: on one actor, with fake surfaces and a clock the test moves.
@MainActor
final class SupervisorBench {
    static let geometry = SurfaceGeometry(size: Size(width: 1800, height: 1169), scale: 2)

    let clock: ManualClock
    let tornDown = Journal<SurfaceID>()
    let supervisor: PlaybackSupervisor
    private(set) var surfaces: [Int: FakeSurface] = [:]
    private(set) var made = 0

    init() {
        let clock = ManualClock(start: Moment.launch)
        let tornDown = tornDown
        self.clock = clock
        supervisor = PlaybackSupervisor(
            location: testLibrary,
            clock: clock,
            now: { clock.date },
            logger: Logger(subsystem: "app.livepaper.tests", category: "supervisor"),
            tearDown: { tornDown.append($0) }
        )
    }

    /// The agent acquires surface `number` for `display`. A layer tree is made only when the supervisor asks for one.
    @discardableResult
    func acquire(_ number: Int, display: Int, preview: Bool = false) async -> SurfaceStoreEffect {
        await supervisor.acquire(.numbered(number), display: .numbered(display), isPreview: preview, geometry: Self.geometry) {
            let surface = FakeSurface()
            self.surfaces[number] = surface
            self.made += 1
            return surface
        }
    }

    func surface(_ number: Int) -> FakeSurface {
        guard let surface = surfaces[number] else { preconditionFailure("surface \(number) was never made") }
        return surface
    }

    func apply(_ state: RenderState) async {
        await supervisor.apply(.read(state)).value
    }

    /// Lets the supervisor's own timers reach their sleep, so that moving the clock wakes them.
    func settle(sleepers: Int) async {
        while clock.sleeperCount < sleepers { await Task.yield() }
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PlaybackSupervisorTests {
    static func state(
        _ displays: RenderState.Display...,
        generation: UInt64 = 1,
        stopped: Bool = false,
        rules: PauseRules = PauseRules(),
        conditions: SensedConditions? = nil
    ) -> RenderState {
        RenderState(generation: generation, isStopped: stopped, displays: displays, pauseRules: rules, conditions: conditions)
    }

    static let stalled = PictureCount(displayed: 0, expected: 60, fed: 0)

    /// Conditions the app sensed at launch: `display` is covered.
    static func covering(_ display: Int) -> SensedConditions {
        SensedConditions(sensedAt: Moment.launch, coveredDisplays: [.numbered(display)])
    }

    // MARK: What surfaces show

    @Test func `an acquired surface shows its display's wallpaper`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1), .numbered(2), generation: 42))

        let effect = await bench.acquire(1, display: 2)

        #expect(effect == .create(.numbered(1)))
        #expect(bench.surface(1).playbackCalls == [.show(.numbered(2), crossfade: false)])
        #expect(bench.supervisor.heartbeat == Heartbeat(generation: 42, flags: [.desktopSurfaceAcquired]))
    }

    @Test func `with no render state a surface shows the neutral colour and the heartbeat says so`() async {
        let bench = SupervisorBench()

        await bench.acquire(1, display: 1)

        #expect(bench.surface(1).playbackCalls == [])
        #expect(bench.supervisor.heartbeat == Heartbeat(generation: 0, flags: [.desktopSurfaceAcquired, .holdingStill]))
    }

    @Test func `a new wallpaper crossfades on a surface that plays`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1)))
        await bench.acquire(1, display: 1)

        await bench.apply(Self.state(.numbered(1, showing: 2), generation: 2))

        #expect(bench.surface(1).playbackCalls == [.show(.numbered(1), crossfade: false), .show(.numbered(2), crossfade: true)])
        #expect(bench.supervisor.heartbeat.generation == 2)
    }

    @Test func `the stopped state holds each display's poster`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1), .numbered(2)))
        await bench.acquire(1, display: 1)
        await bench.acquire(2, display: 2)

        await bench.apply(Self.state(.numbered(1), .numbered(2), generation: 2, stopped: true))

        #expect(bench.surface(1).playbackCalls.last == .holdStill(.numbered(1)))
        #expect(bench.surface(2).playbackCalls.last == .holdStill(.numbered(2)))
        #expect(bench.supervisor.heartbeat == Heartbeat(generation: 2, flags: [.desktopSurfaceAcquired, .holdingStill]))
    }

    @Test func `under Pause All each display pauses in place, and Resume All plays it on, a display's own pause kept`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1), .numbered(2)))
        await bench.acquire(1, display: 1)
        await bench.acquire(2, display: 2)

        await bench.apply(Self.state(.numbered(1, userPaused: true), .numbered(2, userPaused: true), generation: 2))
        let whilePaused = bench.supervisor.heartbeat
        await bench.apply(Self.state(.numbered(1), .numbered(2, userPaused: true), generation: 3))

        #expect(bench.surface(1).playbackCalls == [.show(.numbered(1), crossfade: false), .pause, .resume])
        #expect(bench.surface(2).playbackCalls == [.show(.numbered(2), crossfade: false), .pause])
        #expect(whilePaused == Heartbeat(generation: 2, flags: [.desktopSurfaceAcquired]), "paused, not holding a still")
    }

    @Test func `an unreadable state keeps what is shown`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1), generation: 5))
        await bench.acquire(1, display: 1)

        await bench.supervisor.apply(.unreadable("unknown schema version 2.0")).value

        #expect(bench.surface(1).playbackCalls == [.show(.numbered(1), crossfade: false)])
        #expect(bench.supervisor.heartbeat.generation == 5)
    }

    @Test func `a state that goes missing shows nothing`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1)))
        await bench.acquire(1, display: 1)

        await bench.supervisor.apply(.missing).value

        #expect(bench.surface(1).playbackCalls == [.show(.numbered(1), crossfade: false), .showNothing])
        #expect(bench.supervisor.heartbeat.flags.contains(.holdingStill))
    }

    @Test func `the preview shows its display's wallpaper and is not the desktop`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1, showing: 3)))

        await bench.acquire(7, display: 1, preview: true)

        #expect(bench.surface(7).playbackCalls == [.show(.numbered(3), crossfade: false)])
        #expect(!bench.supervisor.heartbeat.flags.contains(.desktopSurfaceAcquired))
        await bench.acquire(1, display: 1)
        #expect(bench.supervisor.heartbeat.flags.contains(.desktopSurfaceAcquired))
    }

    // MARK: The agent's reconnects

    @Test func `a re-acquire within the grace reuses the surface and lays it out`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1)))
        await bench.acquire(1, display: 1)
        bench.clock.advance(by: .seconds(1))
        bench.supervisor.invalidate(.numbered(1))
        #expect(!bench.supervisor.heartbeat.flags.contains(.desktopSurfaceAcquired))

        bench.clock.advance(by: .seconds(14))
        let effect = await bench.acquire(1, display: 1)

        #expect(effect == .reuse(.numbered(1)))
        #expect(bench.made == 1)
        #expect(bench.surface(1).calls.entries.last == .layout(SupervisorBench.geometry))
        #expect(bench.supervisor.heartbeat.flags.contains(.desktopSurfaceAcquired))
        #expect(bench.clock.sleeperCount == 0, "its teardown is cancelled")
    }

    @Test func `an abandoned surface is torn down after the grace and a returning display gets its wallpaper`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1, showing: 4)))
        await bench.acquire(1, display: 1)
        bench.supervisor.invalidate(.numbered(1))
        await bench.settle(sleepers: 1)

        bench.clock.advance(by: .seconds(14.9))
        #expect(bench.clock.sleeperCount == 1, "still within its grace")
        bench.clock.advance(by: .milliseconds(100))
        await bench.tornDown.wait(for: 1)
        await bench.surface(1).calls.wait(for: 2)

        #expect(bench.tornDown.entries == [.numbered(1)])
        #expect(bench.supervisor.entry(for: .numbered(1)) == nil)
        #expect(bench.surface(1).playbackCalls == [.show(.numbered(4), crossfade: false), .showNothing])
        let effect = await bench.acquire(2, display: 1)
        #expect(effect == .create(.numbered(2)))
        #expect(bench.surface(2).playbackCalls == [.show(.numbered(4), crossfade: false)])
    }

    @Test func `a surface within its grace follows a new state, so stopping releases its decoder too`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1)))
        await bench.acquire(1, display: 1, preview: true)
        bench.supervisor.invalidate(.numbered(1))

        await bench.apply(Self.state(.numbered(1), generation: 2, stopped: true))

        #expect(bench.surface(1).playbackCalls == [.show(.numbered(1), crossfade: false), .holdStill(.numbered(1))])
    }

    @Test func `an unknown surface cannot be invalidated`() {
        let bench = SupervisorBench()

        #expect(!bench.supervisor.invalidate(.numbered(9)))
    }

    @Test func `a new geometry lays out a display's desktop surfaces, not its preview`() async {
        let bench = SupervisorBench()
        await bench.acquire(1, display: 1)
        await bench.acquire(2, display: 1, preview: true)
        await bench.acquire(3, display: 2)
        let geometry = SurfaceGeometry(size: Size(width: 1280, height: 1024), scale: 1)

        bench.supervisor.layout(display: .numbered(1), geometry: geometry)

        #expect(bench.surface(1).calls.entries == [.layout(geometry)])
        #expect(bench.surface(2).calls.entries.isEmpty)
        #expect(bench.surface(3).calls.entries.isEmpty)
    }

    // MARK: What the extension reads and relays

    @Test func `the supervisor says what it knows of a surface`() async {
        let bench = SupervisorBench()
        await bench.acquire(1, display: 2)
        await bench.acquire(3, display: 2, preview: true)
        #expect(bench.supervisor.entry(for: .numbered(1)) == SurfaceStore.Entry(display: .numbered(2), isPreview: false))
        #expect(bench.supervisor.entry(for: .numbered(3)) == SurfaceStore.Entry(display: .numbered(2), isPreview: true))

        await bench.supervisor.update(.numbered(1), mode: .locked).value
        bench.clock.advance(by: .seconds(1))
        bench.supervisor.invalidate(.numbered(1))

        let entry = bench.supervisor.entry(for: .numbered(1))
        #expect(entry == SurfaceStore.Entry(display: .numbered(2), isPreview: false, mode: .locked, invalidatedAt: Moment.after(1)))
        #expect(entry?.isLive == false)
        #expect(bench.supervisor.entry(for: .numbered(9)) == nil)
    }

    @Test func `a new geometry for one surface lays out that surface alone, the preview too`() async {
        let bench = SupervisorBench()
        await bench.acquire(1, display: 1)
        await bench.acquire(2, display: 1, preview: true)
        let geometry = SurfaceGeometry(size: Size(width: 640, height: 400), scale: 2)

        bench.supervisor.layout(.numbered(2), geometry: geometry)
        bench.supervisor.layout(.numbered(9), geometry: geometry)

        #expect(bench.surface(2).calls.entries == [.layout(geometry)])
        #expect(bench.surface(1).calls.entries.isEmpty)
    }

    @Test func `an update that names no surface is a moment to check all the same`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1)))
        await bench.acquire(1, display: 1)

        await bench.supervisor.agentUpdated().value

        #expect(bench.surface(1).countsTaken == 1)
    }

    // MARK: Decisions

    @Test func `a covered display pauses and plays again when its conditions expire`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1)))
        await bench.acquire(1, display: 1)

        await bench.apply(Self.state(.numbered(1), generation: 2, conditions: Self.covering(1)))
        #expect(bench.surface(1).playbackCalls == [.show(.numbered(1), crossfade: false), .pause])
        await bench.settle(sleepers: 1)
        bench.clock.advance(by: .seconds(30))
        #expect(bench.clock.sleeperCount == 1, "conditions 30 s old still count")
        bench.clock.advance(by: .seconds(1))
        await bench.surface(1).calls.wait(for: 3)

        #expect(bench.surface(1).playbackCalls == [.show(.numbered(1), crossfade: false), .pause, .resume])
    }

    @Test func `the user's pause does not expire`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1)))
        await bench.acquire(1, display: 1)

        await bench.apply(Self.state(.numbered(1, userPaused: true), conditions: Self.covering(1)))

        #expect(bench.surface(1).playbackCalls == [.show(.numbered(1), crossfade: false), .pause])
        #expect(bench.clock.sleeperCount == 0)
    }

    @Test func `a sleeping display suspends and plays once its conditions go stale`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1)))
        await bench.acquire(1, display: 1)
        await bench.apply(Self.state(.numbered(1), conditions: SensedConditions(sensedAt: Moment.launch, asleepDisplays: [.numbered(1)])))
        #expect(bench.surface(1).playbackCalls.last == .suspend)

        // The Mac sleeps for an hour and the app has not written since.
        bench.clock.advance(by: .seconds(3600))
        await bench.surface(1).calls.wait(for: 3)

        #expect(bench.surface(1).playbackCalls == [.show(.numbered(1), crossfade: false), .suspend, .resume])
    }

    @Test func `a wake decides again and checks a second later`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1)))
        await bench.acquire(1, display: 1)
        bench.surface(1).lose()

        let wake = bench.supervisor.wake()
        await bench.settle(sleepers: 1)
        bench.clock.advance(by: .milliseconds(900))
        #expect(bench.clock.sleeperCount == 1, "not yet")
        bench.clock.advance(by: .milliseconds(100))
        await wake.value

        #expect(bench.surface(1).playbackCalls == [.show(.numbered(1), crossfade: false), .show(.numbered(1), crossfade: false)])
        #expect(bench.surface(1).countsTaken == 1)
    }
}
