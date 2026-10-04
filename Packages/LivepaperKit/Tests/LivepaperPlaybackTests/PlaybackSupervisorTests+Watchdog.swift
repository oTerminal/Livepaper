import Testing
import LivepaperCore
import LivepaperPlayback

/// The watchdog, driven as the extension drives it: which surfaces a check
/// judges, the ladder, the app's recoveries, and checks that overlap.
@MainActor
extension PlaybackSupervisorTests {
    @Test func `a check judges the desktop surfaces that play on screen`() async {
        let bench = SupervisorBench()
        let covered = SensedConditions(sensedAt: Moment.launch, coveredDisplays: [.numbered(2)])
        await bench.apply(Self.state(.numbered(1), .numbered(2), rules: PauseRules(whenDesktopCovered: false), conditions: covered))
        await bench.acquire(1, display: 1)
        await bench.acquire(2, display: 2)
        await bench.acquire(3, display: 1, preview: true)

        await bench.supervisor.check().value

        #expect(bench.surface(1).countsTaken == 1)
        #expect(bench.surface(2).countsTaken == 0, "covered: not composited")
        #expect(bench.surface(3).countsTaken == 0, "the preview")
    }

    @Test func `a covered display on the lock screen is judged`() async {
        let bench = SupervisorBench()
        let covered = SensedConditions(sensedAt: Moment.launch, coveredDisplays: [.numbered(1)], locked: true)
        await bench.apply(Self.state(.numbered(1), conditions: covered))
        await bench.acquire(1, display: 1)

        await bench.supervisor.update(.numbered(1), mode: .locked).value

        #expect(bench.surface(1).playbackCalls == [.show(.numbered(1), crossfade: false)])
        #expect(bench.surface(1).countsTaken == 1)
    }

    @Test func `a stall climbs the ladder inside the process, then asks the app for the agent`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1)))
        await bench.acquire(1, display: 1)
        bench.surface(1).counts = [Self.stalled, Self.stalled, Self.stalled, Self.stalled]

        await bench.supervisor.unlock().value

        #expect(bench.surface(1).recoveries == [.flush, .rebuildSurface, .rebuildPipeline])
        #expect(bench.surface(1).countsTaken == 4)
        #expect(bench.supervisor.heartbeat.flags.contains(.restartAgentRequested))

        await bench.supervisor.check().value

        #expect(!bench.supervisor.heartbeat.flags.contains(.restartAgentRequested), "a later healthy check clears it")
    }

    @Test func `a surface the engine feeds but the window server does not composite is left alone`() async {
        let bench = SupervisorBench()
        // The render state does not know the display is covered: the app is late, or its sensing missed it.
        await bench.apply(Self.state(.numbered(1)))
        await bench.acquire(1, display: 1)
        bench.surface(1).counts = [PictureCount(displayed: 0, expected: 60, fed: 60)]

        await bench.supervisor.check().value

        #expect(bench.surface(1).recoveries == [])
        #expect(bench.surface(1).countsTaken == 1, "nothing was tried, so no check follows")
        #expect(!bench.supervisor.heartbeat.flags.contains(.restartAgentRequested))

        await bench.supervisor.recover(.flush)?.value

        #expect(bench.surface(1).recoveries == [], "nor is it a stalled surface for the app's recovery")
    }

    @Test func `a recovery that works ends the ladder`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1)))
        await bench.acquire(1, display: 1)
        bench.surface(1).counts = [Self.stalled]

        await bench.supervisor.check().value

        #expect(bench.surface(1).recoveries == [.flush])
        #expect(bench.surface(1).countsTaken == 2)
        #expect(!bench.supervisor.heartbeat.flags.contains(.restartAgentRequested))
    }

    @Test func `the app's recovery runs at once on the stalled surfaces`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1), .numbered(2)))
        await bench.acquire(1, display: 1)
        await bench.acquire(2, display: 2)
        bench.surface(1).counts = [Self.stalled, Self.stalled, Self.stalled, Self.stalled]
        await bench.supervisor.check().value

        await bench.supervisor.recover(.rebuildSurface)?.value

        #expect(bench.surface(1).recoveries == [.flush, .rebuildSurface, .rebuildPipeline, .rebuildSurface])
        #expect(bench.surface(2).recoveries == [])
        #expect(!bench.supervisor.heartbeat.flags.contains(.restartAgentRequested), "the check after it found pictures")
    }

    @Test func `the agent restart is the app's own, so asking the supervisor for it starts nothing`() {
        let bench = SupervisorBench()

        #expect(bench.supervisor.recover(.restartAgent) == nil)
    }

    @Test func `a check asked for while one runs follows it, and waiting for it waits for both`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1)))
        await bench.acquire(1, display: 1)
        let gate = Gate()
        bench.surface(1).countGate = gate
        let first = bench.supervisor.check()
        await bench.surface(1).calls.wait(for: 2)

        let second = bench.supervisor.unlock()
        await Task.yield()
        gate.open()
        await second.value

        #expect(bench.surface(1).countsTaken == 2)
        await first.value
    }

    @Test func `a surface that goes takes its restart request with it`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1)))
        await bench.acquire(1, display: 1)
        bench.surface(1).counts = [Self.stalled, Self.stalled, Self.stalled, Self.stalled]
        await bench.supervisor.check().value

        bench.supervisor.invalidate(.numbered(1))

        #expect(!bench.supervisor.heartbeat.flags.contains(.restartAgentRequested))
    }

    @Test func `a paused surface is not judged`() async {
        let bench = SupervisorBench()
        await bench.apply(Self.state(.numbered(1, userPaused: true)))
        await bench.acquire(1, display: 1)

        await bench.supervisor.check().value

        #expect(bench.surface(1).countsTaken == 0)
    }
}
