import Foundation
import LivepaperCore
import LivepaperSystem
import Testing

/// Not selected is not silence. WallpaperAgent launches the extension only when
/// Livepaper is the system wallpaper, so a user who chose another hears nothing
/// from it. Before an automatic restart the host reads what the wallpaper store
/// says (read only, through `WallpaperStore`) and the shared record of the last
/// restart: named nowhere, Livepaper is not selected and nothing is restarted
/// (no agent restart on an ordinary launch).
extension HostStatusReducerTests {
    struct Silence: Equatable, Sendable {
        var status: RenderHostStatus
        var steps: [HostScript.Step]
    }

    /// The first two levels, which no extension is there to receive before a heartbeat.
    static let skipped: [HostScript.Step] = [
        .init(20_001, .skip(.flush)),
        .init(30_001, .skip(.rebuildSurface)),
        .init(30_001, .skip(.rebuildPipeline)),
    ]

    static let silenceRows: [Row<StoreSelection, Silence>] = [
        Row(
            "named nowhere in the store: not selected, and nothing restarted",
            .notSelected,
            Silence(status: .notSelected, steps: skipped)
        ),
        Row(
            "named in the store and silent: the agent is restarted once, as the ladder says",
            .selected,
            Silence(status: .recovering(.restartAgent), steps: skipped + [.init(30_001, .restart(.silence))])
        ),
        Row(
            "a store that cannot be read: the agent is restarted once, as the ladder says",
            .unreadable,
            Silence(status: .recovering(.restartAgent), steps: skipped + [.init(30_001, .restart(.silence))])
        ),
    ]

    @Test(arguments: silenceRows)
    func `silence from launch asks the store before restarting the agent`(row: Row<StoreSelection, Silence>) {
        var script = HostScript(store: row.input)

        script.runClock(until: 86_400)

        #expect(Silence(status: script.reducer.status, steps: script.steps) == row.expected)
        #expect(script.reads == 1)
        #expect(script.reducer.nextCheck == nil)
    }

    @Test func `a heartbeat after not selected is heard as it says`() {
        var script = HostScript(store: .notSelected)
        script.runClock(until: 100)

        script.heartbeat(at: 101)

        #expect(script.reducer.status == .live)
        #expect(script.reducer.nextCheck.map(Moment.millisecond(of:)) == 116_001)
    }

    @Test func `the store is read before a restart only, never while heartbeats come`() {
        var script = HostScript(store: .notSelected)
        script.heartbeats(from: 3, through: 600)
        #expect(script.reads == 0)

        script.runClock(until: 700)

        #expect(script.reads == 1)
        #expect(script.restarts.isEmpty)
        #expect(script.reducer.status == .notSelected)
    }

    @Test func `not selected lasts through a wake, and the store is read again at the next restart`() {
        var script = HostScript(store: .notSelected)
        script.runClock(until: 100)

        script.send(.systemWillSleep)
        script.send(.systemDidWake(at: Moment.after(1000)))
        #expect(script.reducer.status == .notSelected)
        script.runClock(until: 1100)

        #expect(script.reads == 2)
        #expect(script.restarts.isEmpty)
        #expect(script.reducer.status == .notSelected)
    }

    @Test func `once the store names Livepaper, the next silence restarts the agent`() {
        var script = HostScript(store: .notSelected)
        script.runClock(until: 100)
        script.store = .selected

        script.send(.systemDidWake(at: Moment.after(1000)))
        script.runClock(until: 1100)

        #expect(script.restarts.map(\.millisecond) == [1_030_001])
        #expect(script.reducer.status == .recovering(.restartAgent))
    }

    // MARK: A restart made elsewhere

    @Test func `a restart recorded elsewhere since activation holds the ladder's restart back ten minutes`() {
        var script = HostScript()
        // Selection's, written to the shared record before its killall.
        script.recordedRestart = Moment.after(10)

        script.runClock(until: 3600)

        #expect(script.steps == Self.skipped + [
            .init(30_001, .refuse(.silence, untilMillisecond: 610_000)),
            .init(610_001, .restart(.silence)),
        ])
        #expect(script.restarts.count == 1)
    }

    @Test func `a heartbeat's request for a restart sees one recorded elsewhere`() {
        var script = HostScript()
        script.heartbeats(from: 3, through: 23)
        script.recordedRestart = Moment.after(25)

        script.heartbeat([.desktopSurfaceAcquired, .spiralDetected], at: 28)

        #expect(script.steps == [.init(28_000, .refuse(.spiral, untilMillisecond: 625_000))])
        #expect(script.reducer.lastAgentRestart.map(Moment.millisecond(of:)) == 25_000)
    }

    @Test func `the status line's button is answered by the host's own record`() {
        var script = HostScript()
        script.heartbeat(at: 3)
        script.recordedRestart = Moment.after(5)

        script.send(.restartRequested(at: Moment.after(10)))

        // The click is not read for: its answer, a restart or a refusal, is told by `lastAgentRestart` moving.
        #expect(script.steps == [.init(10_000, .restart(.user))])
        #expect(script.reads == 0)
    }
}
