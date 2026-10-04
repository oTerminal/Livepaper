import Foundation
import LivepaperCore
import LivepaperSystem
import LivepaperTestSupport
import os
import Testing

// Some tests wait on the client's streams; one that never yields fails the test instead of hanging the run.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ExtensionHostClientTests {
    let home: TemporaryFolder
    let location: LibraryLocation
    let clock = ManualWallClock()
    let notifier = RecordingNotifier()
    let agent = FakeAgentRestarter()
    let sleep = FakeSleepSensor()
    let restarts = MemoryAgentRestartStore()
    let wallpaperStore = FakeStoreReader()
    let client: ExtensionHostClient

    init() throws {
        home = try TemporaryFolder()
        location = LibraryLocation(home: home.url)
        client = ExtensionHostClient(
            location: location, notifier: notifier, agent: agent, restartStore: restarts, wallpaperStore: wallpaperStore,
            clock: clock, sleep: sleep, logger: Logger(subsystem: "app.livepaper.tests", category: HostLog.category)
        )
    }

    static func state(generation: UInt64 = 5) throws -> RenderState {
        let wallpaper = WallpaperID(uuid: UUID(uuidString: "AAAAAAAA-0000-0000-0000-000000000001") ?? UUID())
        let display = RenderState.Display(
            identity: .numbered(1),
            wallpaper: wallpaper,
            optimisedCopy: try LibraryPath("wallpapers/\(wallpaper)/wallpaper.mov"),
            poster: try LibraryPath("wallpapers/\(wallpaper)/poster.heic"),
            presentation: Presentation(),
            volume: 0,
            userPaused: false
        )
        return RenderState(generation: generation, displays: [display], pauseRules: PauseRules(), conditions: nil)
    }

    func stateOnDisk() throws -> RenderState {
        try RenderState.decode(Data(contentsOf: location.renderState))
    }

    /// Lets the client's own tasks run until `condition` holds, or gives up.
    func settle(until condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
    }

    // MARK: Activation and the heartbeat

    @Test func `activating listens for the heartbeat and reports connecting`() async throws {
        try await client.activate()

        #expect(notifier.isObserving(HostNotification.heartbeat))
        #expect(client.currentStatus == .connecting)
        var statuses = client.status.makeAsyncIterator()
        #expect(await statuses.next() == .connecting)
    }

    @Test func `activating fails when the heartbeat cannot be observed`() async {
        notifier.refusesToObserve = true

        await #expect(throws: ExtensionHostError.heartbeatUnobservable) { try await client.activate() }
        #expect(client.currentStatus == .stopped)
    }

    @Test func `each session starts with the playback metrics probe off`() async throws {
        try await client.activate()

        #expect(notifier.posts(of: HostNotification.playbackMetrics) == [.init(name: HostNotification.playbackMetrics.name, state: 0)])
    }

    @Test func `the heartbeat gives the status, and a new status stream starts with it`() async throws {
        try await client.activate()
        var statuses = client.status.makeAsyncIterator()

        notifier.deliver(Heartbeat(generation: 5, flags: .desktopSurfaceAcquired))

        #expect(await statuses.next() == .connecting)
        #expect(await statuses.next() == .live)
        #expect(client.lastHeartbeat == Heartbeat(generation: 5, flags: .desktopSurfaceAcquired))
        var later = client.status.makeAsyncIterator()
        #expect(await later.next() == .live)
    }

    @Test func `silence from launch restarts the agent, posting nothing to an extension that is not there`() async throws {
        try await client.activate()

        clock.advance(toSecond: 3600)

        #expect(notifier.posts(of: HostNotification.recover).isEmpty)
        var asked = agent.asked.makeAsyncIterator()
        #expect(await asked.next() == 1)
        #expect(client.lastAgentRestart.map(Moment.millisecond(of:)) == 30_001)
        #expect(client.currentStatus == .recovering(.restartAgent))
        #expect(clock.scheduled.isEmpty)
    }

    @Test func `silence after a heartbeat climbs the ladder in the extension, then restarts the agent once`() async throws {
        try await client.activate()
        clock.advance(toSecond: 3)
        notifier.deliver(Heartbeat(generation: 5, flags: .desktopSurfaceAcquired))

        clock.advance(toSecond: 3600)

        #expect(notifier.posts(of: HostNotification.recover).map(\.state) == [0, 1, 2])
        var asked = agent.asked.makeAsyncIterator()
        #expect(await asked.next() == 1)
        #expect(client.lastAgentRestart.map(Moment.millisecond(of:)) == 48_001)
        #expect(client.currentStatus == .recovering(.restartAgent))
    }

    @Test func `a heartbeat keeps one check waiting, at the moment it expires`() async throws {
        try await client.activate()
        clock.advance(toSecond: 3)

        notifier.deliver(Heartbeat(generation: 5, flags: .desktopSurfaceAcquired))
        clock.advance(toSecond: 8)
        notifier.deliver(Heartbeat(generation: 5, flags: .desktopSurfaceAcquired))

        #expect(clock.scheduled.map(Moment.millisecond(of:)) == [23_001])
        #expect(notifier.posts(of: HostNotification.recover).isEmpty)
    }

    @Test func `a heartbeat that asks for it restarts the agent`() async throws {
        try await client.activate()

        notifier.deliver(Heartbeat(generation: 5, flags: [.desktopSurfaceAcquired, .spiralDetected]))

        var asked = agent.asked.makeAsyncIterator()
        #expect(await asked.next() == 1)
        #expect(client.currentStatus == .recovering(.restartAgent))
    }

    @Test func `a wake gives the extension a fresh grace period`() async throws {
        try await client.activate()
        clock.advance(toSecond: 3)
        notifier.deliver(Heartbeat(generation: 5, flags: .desktopSurfaceAcquired))

        sleep.send(.willSleep)
        await settle { clock.scheduled.isEmpty }
        #expect(clock.scheduled.isEmpty)
        clock.advance(toSecond: 4000)
        sleep.send(.didWake)
        await settle { !clock.scheduled.isEmpty }

        #expect(clock.scheduled.map(Moment.millisecond(of:)) == [4_020_001])
        #expect(client.currentStatus == .live)
    }

    @Test func `a check that fell due in a sleep nobody heard posts nothing when it fires at the wake`() async throws {
        try await client.activate()
        clock.advance(toSecond: 3)
        notifier.deliver(Heartbeat(generation: 5, flags: .desktopSurfaceAcquired))

        clock.sleep(untilSecond: 4000)

        #expect(notifier.posts(of: HostNotification.recover).isEmpty)
        #expect(client.lastAgentRestart == nil)
        #expect(client.currentStatus == .live)
        #expect(clock.scheduled.map(Moment.millisecond(of:)) == [4_020_001])
    }

    // MARK: Recovery asked for by the app

    @Test func `the lower levels are posted for the extension to try`() async throws {
        try await client.activate()

        await client.recover(.flush)
        await client.recover(.rebuildPipeline)

        #expect(notifier.posts(of: HostNotification.recover).map(\.state) == [0, 2])
        #expect(agent.restarts == 0)
    }

    @Test func `restarting the agent goes through the ten-minute gap`() async throws {
        try await client.activate()

        await client.recover(.restartAgent)
        clock.advance(toSecond: 15)
        await client.recover(.restartAgent)

        #expect(agent.restarts == 1)
        #expect(notifier.posts(of: HostNotification.recover).isEmpty)
    }

    @Test func `a restart is recorded for the next launch`() async throws {
        try await client.activate()
        clock.advance(toSecond: 10)

        await client.recover(.restartAgent)

        #expect(restarts.lastRestart.map(Moment.millisecond(of:)) == 10_000)
    }

    @Test func `a restart recorded by the last launch keeps the ten-minute gap`() async throws {
        restarts.lastRestart = Moment.after(-60)
        try await client.activate()

        await client.recover(.restartAgent)
        clock.advance(toSecond: 540)
        await client.recover(.restartAgent)

        #expect(agent.restarts == 1)
        #expect(client.lastAgentRestart.map(Moment.millisecond(of:)) == 540_000)
    }

    // MARK: The render state

    @Test func `applying replaces the render state and tells the extension`() async throws {
        let state = try Self.state()

        await client.apply(state)

        #expect(try stateOnDisk() == state)
        #expect(notifier.posts(of: HostNotification.renderStateChanged).count == 1)
        #expect(client.lastApplied == state)
    }

    @Test func `applying the same state again changes nothing`() async throws {
        let state = try Self.state()
        await client.apply(state)

        await client.apply(state)

        #expect(notifier.posts(of: HostNotification.renderStateChanged).count == 1)
    }

    @Test func `deactivating writes the stopped form of the last state, and stops`() async throws {
        let state = try Self.state(generation: 5)
        try await client.activate()
        await client.apply(state)

        await client.deactivate()

        let stopped = try stateOnDisk()
        #expect(stopped.isStopped)
        #expect(stopped.generation == 6)
        #expect(stopped.displays == state.displays)
        #expect(notifier.posts(of: HostNotification.renderStateChanged).count == 2)
        #expect(client.currentStatus == .stopped)
        #expect(!notifier.isObserving(HostNotification.heartbeat))
        #expect(clock.scheduled.isEmpty)
    }

    @Test func `deactivating before anything was applied stops the state already on disk`() async throws {
        try FileManager.default.createDirectory(at: location.root, withIntermediateDirectories: true)
        try Self.state(generation: 9).encode().write(to: location.renderState)
        try await client.activate()

        await client.deactivate()

        let stopped = try stateOnDisk()
        #expect(stopped.isStopped)
        #expect(stopped.generation == 10)
    }

    @Test func `a heartbeat after deactivating changes nothing`() async throws {
        try await client.activate()
        await client.deactivate()

        notifier.deliver(Heartbeat(generation: 5, flags: .desktopSurfaceAcquired))

        #expect(client.currentStatus == .stopped)
    }

    // MARK: The developer menu

    @Test func `playback metrics and a check are asked of the extension`() async throws {
        try await client.activate()

        client.setPlaybackMetrics(true)
        client.requestCheck()
        client.setPlaybackMetrics(false)

        #expect(notifier.posts.suffix(3) == [
            .init(name: HostNotification.playbackMetrics.name, state: 1),
            .init(name: HostNotification.check.name, state: nil),
            .init(name: HostNotification.playbackMetrics.name, state: 0),
        ])
    }

    @Test func `deactivating switches the metrics probe off`() async throws {
        try await client.activate()
        client.setPlaybackMetrics(true)

        await client.deactivate()

        #expect(notifier.posts(of: HostNotification.playbackMetrics).last?.state == 0)
        #expect(!client.isPlaybackMetricsOn)
    }

    @Test func `the probe lasts the session: activating again after a deactivate switches it back on`() async throws {
        try await client.activate()
        client.setPlaybackMetrics(true)

        await client.deactivate()
        let whilePaused = client.isPlaybackMetricsOn
        try await client.activate()

        #expect(!whilePaused, "off while the extension holds its stills, as the menu's checkmark says")
        #expect(client.isPlaybackMetricsOn)
        #expect(notifier.posts(of: HostNotification.playbackMetrics).last?.state == 1)
    }

    @Test func `a probe switched off before a deactivate stays off after it`() async throws {
        try await client.activate()
        client.setPlaybackMetrics(true)
        client.setPlaybackMetrics(false)

        await client.deactivate()
        try await client.activate()

        #expect(!client.isPlaybackMetricsOn)
        #expect(notifier.posts(of: HostNotification.playbackMetrics).last?.state == 0)
    }
}
