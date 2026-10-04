import Foundation
import LivepaperCore
import LivepaperSystem
import Testing

/// Drives the reducer as the client does: events as they come, and a tick at
/// each `nextCheck`, with the times written down in milliseconds since launch.
/// What the reducer asks to read before an automatic restart is answered at
/// once, as the client answers it, from `store` and `recordedRestart`.
struct HostScript {
    /// An action, with any time in it in milliseconds since launch.
    enum Did: Equatable {
        case post(RecoveryLevel)
        case skip(RecoveryLevel)
        case restart(AgentRestartReason)
        case refuse(AgentRestartReason, untilMillisecond: Int?)

        init?(_ action: HostAction) {
            switch action {
            case .postRecover(let level): self = .post(level)
            case .recoverSkipped(let level): self = .skip(level)
            case .restartAgent(let reason): self = .restart(reason)
            case .restartRefused(let reason, .tooSoon(let allowedFrom)):
                self = .refuse(reason, untilMillisecond: Moment.millisecond(of: allowedFrom))
            case .restartRefused(let reason, .awaitingHeartbeat):
                self = .refuse(reason, untilMillisecond: nil)
            case .readBeforeRestart:
                return nil
            }
        }
    }

    struct Step: Equatable, CustomStringConvertible {
        var millisecond: Int
        var did: Did

        init(_ millisecond: Int, _ did: Did) {
            self.millisecond = millisecond
            self.did = did
        }

        var description: String { "\(millisecond) ms: \(did)" }
    }

    var reducer = HostStatusReducer(timing: .standard)
    var steps: [Step] = []
    /// What the wallpaper store says of Livepaper when the reducer reads it.
    var store: StoreSelection
    /// The shared record of the last restart (`AgentRestartStore`): the reducer's
    /// own restarts go there, and a test can write one made elsewhere, as Selection does.
    var recordedRestart: Date?
    /// How many times the reducer read before a restart.
    private(set) var reads = 0

    init(activatedAt seconds: Double = 0, lastAgentRestartAt restartSecond: Double? = nil, store: StoreSelection = .selected) {
        self.store = store
        recordedRestart = restartSecond.map(Moment.after)
        send(.activated(at: Moment.after(seconds), lastAgentRestart: recordedRestart))
    }

    mutating func send(_ event: HostEvent, at date: Date? = nil) {
        let when = date ?? event.time ?? Moment.launch
        var actions = reducer.reduce(event)
        while let read = actions.firstIndex(where: \.isReadBeforeRestart) {
            guard case .readBeforeRestart(let reason) = actions.remove(at: read) else { break }
            reads += 1
            actions += reducer.reduce(.readForRestart(reason, store: store, lastAgentRestart: recordedRestart, at: when))
        }
        if actions.contains(where: { if case .restartAgent = $0 { true } else { false } }) {
            recordedRestart = reducer.lastAgentRestart
        }
        steps += actions.compactMap { action in Did(action).map { Step(Moment.millisecond(of: when), $0) } }
    }

    mutating func heartbeat(_ flags: Heartbeat.Flags = .desktopSurfaceAcquired, at seconds: Double) {
        send(.heartbeat(Heartbeat(generation: 1, flags: flags), at: Moment.after(seconds)))
    }

    /// Heartbeats every 5 s, as the extension sends them, from `start` up to and including `end`.
    mutating func heartbeats(_ flags: Heartbeat.Flags = .desktopSurfaceAcquired, from start: Double, through end: Double) {
        for second in stride(from: start, through: end, by: 5) {
            runClock(until: second)
            heartbeat(flags, at: second)
        }
    }

    /// Ticks whenever the reducer asks to be checked, up to `seconds` after launch.
    mutating func runClock(until seconds: Double) {
        let end = Moment.after(seconds)
        var ticks = 0
        while let next = reducer.nextCheck, next <= end {
            send(.tick(at: next))
            ticks += 1
            precondition(ticks < 10_000, "the reducer keeps asking to be checked")
        }
    }

    var restarts: [Step] {
        steps.filter { if case .restart = $0.did { true } else { false } }
    }
}

struct HostStatusReducerTests {
    @Test func `activating reports connecting and waits for the grace period`() {
        let script = HostScript()

        #expect(script.reducer.status == .connecting)
        #expect(script.reducer.nextCheck.map(Moment.millisecond(of:)) == 20_001)
        #expect(script.steps.isEmpty)
    }

    static let heartbeatRows: [Row<Heartbeat.Flags, RenderHostStatus>] = [
        Row("a desktop surface means Livepaper is the wallpaper", [.desktopSurfaceAcquired], .live),
        Row("a heartbeat without a desktop surface means Livepaper is not selected", [], .notSelected),
        Row("the preview alone is not selected", [.holdingStill], .notSelected),
        Row("a still on the desktop is still live", [.desktopSurfaceAcquired, .holdingStill], .live),
        Row("a failed self-check makes the host unavailable", [.selfCheckFailed], .unavailable),
        Row("a failed self-check wins over the desktop flag", [.selfCheckFailed, .desktopSurfaceAcquired], .unavailable),
    ]

    @Test(arguments: heartbeatRows)
    func `the heartbeat's flags give the status`(row: Row<Heartbeat.Flags, RenderHostStatus>) {
        var script = HostScript()

        script.heartbeat(row.input, at: 3)

        #expect(script.reducer.status == row.expected)
    }

    @Test func `a heartbeat moves the next check to where it expires`() {
        var script = HostScript()

        script.heartbeats(from: 3, through: 28)

        #expect(script.reducer.nextCheck.map(Moment.millisecond(of:)) == 43_001)
        #expect(script.steps.isEmpty)
    }

    @Test func `silence from launch skips the levels nobody can receive and restarts the agent a step after the grace period`() {
        var script = HostScript()

        script.runClock(until: 3600)

        #expect(script.steps == [
            .init(20_001, .skip(.flush)),
            .init(30_001, .skip(.rebuildSurface)),
            .init(30_001, .skip(.rebuildPipeline)),
            .init(30_001, .restart(.silence)),
        ])
        #expect(script.reducer.status == .recovering(.restartAgent))
    }

    @Test func `silence from launch reports the first level until the restart is due`() {
        var script = HostScript()

        script.runClock(until: 25)

        #expect(script.reducer.status == .recovering(.flush))
        #expect(script.reducer.nextCheck.map(Moment.millisecond(of:)) == 30_001)
    }

    @Test func `silence reports the level it has reached`() {
        var script = HostScript()
        script.heartbeats(from: 3, through: 23)

        script.runClock(until: 50)

        #expect(script.reducer.status == .recovering(.rebuildSurface))
    }

    @Test func `silence after heartbeats climbs the whole ladder from when the last one expires`() {
        var script = HostScript()
        script.heartbeats(from: 3, through: 23)

        script.runClock(until: 70)

        #expect(script.steps == [
            .init(38_001, .post(.flush)),
            .init(48_001, .post(.rebuildSurface)),
            .init(58_001, .post(.rebuildPipeline)),
            .init(68_001, .restart(.silence)),
        ])
    }

    @Test func `a heartbeat after the restart ends the recovery`() {
        var script = HostScript()
        script.runClock(until: 51)

        script.heartbeat(at: 51.5)

        #expect(script.reducer.status == .live)
        #expect(!script.reducer.restartUnanswered)
        #expect(script.reducer.lastAgentRestart.map(Moment.millisecond(of:)) == 30_001)
    }

    @Test func `when the extension stays silent the agent is restarted once, not every ten minutes`() {
        var script = HostScript()

        script.runClock(until: 86_400)

        #expect(script.restarts.map(\.millisecond) == [30_001])
        #expect(script.reducer.restartUnanswered)
        #expect(script.reducer.nextCheck == nil)
        #expect(script.reducer.status == .recovering(.restartAgent))
    }

    @Test func `an unanswered restart still lets the status line's button restart the agent after ten minutes`() {
        var script = HostScript()
        script.runClock(until: 700)

        script.send(.restartRequested(at: Moment.after(700)))

        #expect(script.restarts.map(\.millisecond) == [30_001, 700_000])
    }

    @Test func `a heartbeat after an unanswered restart lets silence restart the agent again`() {
        var script = HostScript()
        script.runClock(until: 900)
        script.heartbeat(at: 900)

        script.runClock(until: 2000)

        // The heartbeat at 900 s expires at 915 s; the ladder reaches the agent 30 s later.
        #expect(script.restarts.map(\.millisecond) == [30_001, 945_001])
    }

    @Test func `a second silence within ten minutes waits for the gap, then restarts`() {
        var script = HostScript()
        script.runClock(until: 51)
        script.heartbeat(at: 52)

        script.runClock(until: 700)

        // Silence from 67 s reaches the agent at 97 s, which is too soon after 30 s;
        // the gap opens at 630 s.
        #expect(script.steps.suffix(2) == [
            .init(97_001, .refuse(.silence, untilMillisecond: 630_001)),
            .init(630_002, .restart(.silence)),
        ])
    }

    @Test func `a restart made before this launch keeps the ten-minute gap`() {
        var script = HostScript(lastAgentRestartAt: -100)

        script.runClock(until: 3600)

        #expect(script.steps.suffix(2) == [
            .init(30_001, .refuse(.silence, untilMillisecond: 500_000)),
            .init(500_001, .restart(.silence)),
        ])
    }

    @Test func `a restart recorded later than the launch counts as made at the launch`() {
        // The clock moved back since: the gap runs from the launch, and no longer.
        var script = HostScript(lastAgentRestartAt: 86_400)

        script.send(.restartRequested(at: Moment.after(10)))

        #expect(script.steps == [.init(10_000, .refuse(.user, untilMillisecond: 600_000))])
    }

    @Test func `activating again keeps a restart made since the record was read`() {
        var script = HostScript(lastAgentRestartAt: -1000)
        script.runClock(until: 51)
        script.send(.deactivated)

        script.send(.activated(at: Moment.after(100), lastAgentRestart: Moment.after(-1000)))

        #expect(script.reducer.lastAgentRestart.map(Moment.millisecond(of:)) == 30_001)
    }

    static let flagRows: [Row<Heartbeat.Flags, AgentRestartReason>] = [
        Row("the spiral flag asks for a restart", [.desktopSurfaceAcquired, .spiralDetected], .spiral),
        Row("the watchdog's request asks for a restart", [.desktopSurfaceAcquired, .restartAgentRequested], .watchdog),
        Row("both flags ask for one restart", [.spiralDetected, .restartAgentRequested], .spiral),
    ]

    @Test(arguments: flagRows)
    func `a heartbeat can ask for the agent to be restarted`(row: Row<Heartbeat.Flags, AgentRestartReason>) {
        var script = HostScript()

        script.heartbeat(row.input, at: 3)

        #expect(script.steps == [.init(3000, .restart(row.expected))])
        #expect(script.reducer.status == .recovering(.restartAgent))
    }

    @Test func `a flag that stays up is refused once, then honoured when the gap opens`() {
        var script = HostScript()
        script.heartbeat(.restartAgentRequested, at: 3)

        script.heartbeats(.restartAgentRequested, from: 8, through: 603)

        #expect(script.steps == [
            .init(3000, .restart(.watchdog)),
            .init(8000, .refuse(.watchdog, untilMillisecond: 603_000)),
            .init(603_000, .restart(.watchdog)),
        ])
    }

    @Test func `after the button's restart, silence waits for a heartbeat before restarting again`() {
        var script = HostScript()
        script.heartbeat(at: 3)
        script.send(.restartRequested(at: Moment.after(10)))

        script.runClock(until: 3600)

        // The heartbeat at 3 s expires at 18 s, inside the grace period that ends at 20 s.
        #expect(script.steps == [
            .init(10_000, .restart(.user)),
            .init(20_001, .post(.flush)),
            .init(28_001, .post(.rebuildSurface)),
            .init(38_001, .post(.rebuildPipeline)),
            .init(48_001, .refuse(.silence, untilMillisecond: nil)),
        ])
        #expect(script.reducer.nextCheck == nil)
    }

    @Test func `the status line's button goes through the ten-minute gap`() {
        var script = HostScript()
        script.heartbeat(at: 3)

        script.send(.restartRequested(at: Moment.after(10)))
        script.send(.restartRequested(at: Moment.after(20)))

        #expect(script.steps == [
            .init(10_000, .restart(.user)),
            .init(20_000, .refuse(.user, untilMillisecond: 610_000)),
        ])
        #expect(script.reducer.status == .recovering(.restartAgent))
    }

    @Test func `deactivating stops the host and its checks`() {
        var script = HostScript()
        script.heartbeat(at: 3)

        script.send(.deactivated)
        script.heartbeat(at: 8)
        script.send(.tick(at: Moment.after(100)))

        #expect(script.reducer.status == .stopped)
        #expect(script.reducer.nextCheck == nil)
        #expect(script.steps.isEmpty)
    }

    @Test func `activating again waits for a new heartbeat`() {
        var script = HostScript()
        script.heartbeat(at: 3)
        script.send(.deactivated)

        script.send(.activated(at: Moment.after(100)))

        #expect(script.reducer.status == .connecting)
        #expect(script.reducer.nextCheck.map(Moment.millisecond(of:)) == 120_001)
    }
}
