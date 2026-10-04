import LivepaperCore
import LivepaperTestSupport
import Testing

@MainActor
struct FakeRenderHostTests {
    struct Refused: Error {}

    @Test func `remembers what it was asked to do, and reports as a host would`() async throws {
        let host = FakeRenderHost()
        let state = RenderState(displays: [], pauseRules: PauseRules(), conditions: nil)
        let statuses = host.status

        try await host.activate()
        await host.apply(state)
        host.report(.live)
        await host.recover(.flush)
        await host.deactivate()

        #expect(host.appliedStates == [state])
        #expect(host.recoveries == [.flush])
        #expect(!host.isActive)
        var reported: [RenderHostStatus] = []
        for await status in statuses.prefix(5) {
            reported.append(status)
        }
        #expect(reported == [.stopped, .connecting, .live, .recovering(.flush), .stopped])
        #expect(host.currentStatus == .stopped)
    }

    @Test func `can take a while to apply, so a fakes run shows the working phase`() async throws {
        let clock = ManualClock(start: Moment.launch)
        let host = FakeRenderHost(clock: clock)
        host.applyDelay = .seconds(1)
        let state = RenderState(displays: [], pauseRules: PauseRules(), conditions: nil)

        let applying = Task { await host.apply(state) }
        while clock.sleeperCount == 0 { await Task.yield() }
        let beforeTheDelay = host.appliedStates
        clock.advance(by: .seconds(1))
        await applying.value

        #expect(beforeTheDelay.isEmpty)
        #expect(host.appliedStates == [state])
    }

    @Test func `can go live a while after activating or recovering, as a heartbeat would arrive`() async throws {
        let clock = ManualClock(start: Moment.launch)
        let host = FakeRenderHost(clock: clock)
        host.liveAfter = .seconds(1)
        var statuses = host.status.makeAsyncIterator()
        let stopped = await statuses.next()

        try await host.activate()
        let connecting = await statuses.next()
        while clock.sleeperCount == 0 { await Task.yield() }
        clock.advance(by: .seconds(1))
        let live = await statuses.next()
        await host.recover(.restartAgent)
        let recovering = await statuses.next()
        while clock.sleeperCount == 0 { await Task.yield() }
        clock.advance(by: .seconds(1))
        let liveAgain = await statuses.next()

        let heard = [stopped, connecting, live, recovering, liveAgain]
        #expect(heard == [.stopped, .connecting, .live, .recovering(.restartAgent), .live])
    }

    @Test func `restarts the agent once in the gap at most, as the real host does, and remembers when`() async {
        let clock = ManualClock(start: Moment.launch)
        let host = FakeRenderHost(clock: clock)
        host.now = { clock.date }
        var statuses = host.status.makeAsyncIterator()
        // Each read starts with the status now.
        _ = await statuses.next()

        let before = host.lastAgentRestart
        await host.recover(.restartAgent)
        let first = host.lastAgentRestart
        let recovering = await statuses.next()
        clock.advance(by: agentRestartGap - .seconds(1))
        await host.recover(.restartAgent)
        let refused = host.lastAgentRestart
        clock.advance(by: .seconds(1))
        await host.recover(.restartAgent)
        host.report(.live)
        let reported = [await statuses.next(), await statuses.next()]

        #expect(before == nil)
        #expect(first == Moment.launch)
        #expect(refused == Moment.launch)
        #expect(host.lastAgentRestart == Moment.after(agentRestartGap / .seconds(1)))
        #expect(host.recoveries == [.restartAgent, .restartAgent, .restartAgent])
        // The refused one said nothing: the host still reported the one before it.
        #expect(recovering == .recovering(.restartAgent))
        #expect(reported == [.recovering(.restartAgent), .live])
    }

    @Test func `can take a while to restart the agent, so a fakes run shows Restart working`() async {
        let clock = ManualClock(start: Moment.launch)
        let host = FakeRenderHost(clock: clock)
        host.agentRestartTime = .seconds(1)

        let restarting = Task { await host.recover(.restartAgent) }
        while clock.sleeperCount == 0 { await Task.yield() }
        let whileRestarting = host.recoveries
        clock.advance(by: .seconds(1))
        await restarting.value

        #expect(whileRestarting.isEmpty)
        #expect(host.recoveries == [.restartAgent])
    }

    @Test func `stopped before it goes live, it stays stopped`() async throws {
        let clock = ManualClock(start: Moment.launch)
        let host = FakeRenderHost(clock: clock)
        host.liveAfter = .seconds(1)
        var statuses = host.status.makeAsyncIterator()

        try await host.activate()
        while clock.sleeperCount == 0 { await Task.yield() }
        await host.deactivate()
        clock.advance(by: .seconds(1))
        for _ in 0..<10 { await Task.yield() }
        host.report(.notSelected)

        var reported: [RenderHostStatus?] = []
        for _ in 0..<4 { reported.append(await statuses.next()) }
        #expect(reported == [.stopped, .connecting, .stopped, .notSelected])
    }

    @Test func `every reader hears it, each starting with the status now`() async throws {
        let host = FakeRenderHost()
        var model = host.status.makeAsyncIterator()
        try await host.activate()
        var selection = host.status.makeAsyncIterator()
        host.report(.live)

        let modelHeard = [await model.next(), await model.next(), await model.next()]
        let selectionHeard = [await selection.next(), await selection.next()]

        #expect(modelHeard == [.stopped, .connecting, .live])
        #expect(selectionHeard == [.connecting, .live])
        #expect(host.currentStatus == .live)
    }

    @Test func `while Livepaper is not the wallpaper, a heartbeat says so, until it is`() async throws {
        let clock = ManualClock(start: Moment.launch)
        let host = FakeRenderHost(clock: clock)
        host.liveAfter = .seconds(1)
        host.isSelected = false
        var statuses = host.status.makeAsyncIterator()
        _ = await statuses.next()

        try await host.activate()
        let connecting = await statuses.next()
        while clock.sleeperCount == 0 { await Task.yield() }
        clock.advance(by: .seconds(1))
        let notSelected = await statuses.next()
        host.isSelected = true
        host.heartbeatLater()
        let connectingAgain = await statuses.next()
        while clock.sleeperCount == 0 { await Task.yield() }
        clock.advance(by: .seconds(1))
        let live = await statuses.next()

        #expect([connecting, notSelected, connectingAgain, live] == [.connecting, .notSelected, .connecting, .live])
    }

    @Test func `can refuse to activate`() async {
        let host = FakeRenderHost()
        host.activationError = Refused()

        await #expect(throws: Refused.self) { try await host.activate() }
        #expect(!host.isActive)
    }
}
