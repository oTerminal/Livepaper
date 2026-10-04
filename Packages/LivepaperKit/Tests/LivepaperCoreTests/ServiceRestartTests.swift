import Foundation
import LivepaperCore
import Testing

struct ServiceRestartTests {
    enum Event: Sendable {
        case started
        /// The host's last restart of WallpaperAgent before and after the request, in seconds after launch.
        case finished(before: Double?, after: Double?, at: Double)
        case host(RenderHostStatus)
        case tick(at: Double)
    }

    static let gap = agentRestartGap / .seconds(1)
    static let wait = ServiceRestart.answerWait / .seconds(1)

    static let rows: [Row<[Event], ServiceRestart.Phase>] = [
        Row("idle until Restart is clicked", [], .idle),
        Row("restarting while the host works", [.started], .restarting),
        Row(
            "a restart made waits for the service to answer, and knows when the next may be tried",
            [.started, .finished(before: nil, after: 10, at: 11)],
            .waitingForAnswer(until: Moment.after(11 + wait), retryFrom: Moment.after(10 + gap))
        ),
        Row(
            "a restart made after an earlier one waits the same way",
            [.started, .finished(before: -5000, after: 10, at: 11)],
            .waitingForAnswer(until: Moment.after(11 + wait), retryFrom: Moment.after(10 + gap))
        ),
        Row(
            "a refused restart, the last one too recent, says when the next may be tried",
            [.started, .finished(before: -100, after: -100, at: 0)],
            .retryFrom(Moment.after(-100 + gap))
        ),
        Row(
            "a host that recorded no restart at all leaves the line to its status",
            [.started, .finished(before: nil, after: nil, at: 0)],
            .idle
        ),
        Row("a finish nobody started changes nothing", [.finished(before: nil, after: 10, at: 11)], .idle),
        Row(
            "still waiting just short of the wait's end",
            [.started, .finished(before: nil, after: 0, at: 0), .tick(at: wait - 0.001)],
            .waitingForAnswer(until: Moment.after(wait), retryFrom: Moment.after(gap))
        ),
        Row(
            "no answer by the wait's end: the line says when the next may be tried",
            [.started, .finished(before: nil, after: 0, at: 0), .tick(at: wait)],
            .retryFrom(Moment.after(gap))
        ),
        Row(
            "the refusal's time passed: back to the host's status",
            [.started, .finished(before: -100, after: -100, at: 0), .tick(at: -100 + gap)],
            .idle
        ),
        Row(
            "a tick before the refusal's time changes nothing",
            [.started, .finished(before: -100, after: -100, at: 0), .tick(at: 60)],
            .retryFrom(Moment.after(-100 + gap))
        ),
        Row("a tick while restarting changes nothing", [.started, .tick(at: 1000)], .restarting),
        Row(
            "the service answering ends the wait",
            [.started, .finished(before: nil, after: 0, at: 0), .host(.live)],
            .idle
        ),
        Row(
            "the service answering that Livepaper is not selected ends the wait too",
            [.started, .finished(before: nil, after: 0, at: 0), .host(.notSelected)],
            .idle
        ),
        Row(
            "the service answering ends a refusal",
            [.started, .finished(before: -100, after: -100, at: 0), .host(.live)],
            .idle
        ),
        Row(
            "the host still not responding keeps the wait",
            [.started, .finished(before: nil, after: 0, at: 0), .host(.recovering(.restartAgent))],
            .waitingForAnswer(until: Moment.after(wait), retryFrom: Moment.after(gap))
        ),
        Row("a change of the host's status while restarting keeps restarting", [.started, .host(.live)], .restarting),
    ]

    @Test(arguments: rows)
    func `restarting, then waiting for an answer, or saying when Restart can next be tried`(row: Row<[Event], ServiceRestart.Phase>) {
        var restart = ServiceRestart()

        for event in row.input {
            switch event {
            case .started: _ = restart.started()
            case .finished(let before, let after, let now):
                restart.finished(lastRestartBefore: before.map(Moment.after), after: after.map(Moment.after), at: Moment.after(now))
            case .host(let status): restart.hostChanged(to: status)
            case .tick(let seconds): restart.tick(at: Moment.after(seconds))
            }
        }

        #expect(restart.phase == row.expected)
    }

    @Test func `a second click while one restart runs is not a second restart`() {
        var restart = ServiceRestart()

        let first = restart.started()
        let second = restart.started()

        #expect(first)
        #expect(!second)
    }

    @Test func `says when a tick has something to do, so the caller can schedule it`() {
        var restart = ServiceRestart()
        let idle = restart.nextTick
        _ = restart.started()
        let restarting = restart.nextTick
        restart.finished(lastRestartBefore: nil, after: Moment.after(0), at: Moment.after(1))
        let waiting = restart.nextTick
        restart.tick(at: Moment.after(1 + Self.wait))
        let refused = restart.nextTick

        #expect(idle == nil)
        #expect(restarting == nil)
        #expect(waiting == Moment.after(1 + Self.wait))
        #expect(refused == Moment.after(Self.gap))
    }

    @Test func `waits as long as the extension has to send its first heartbeat`() {
        #expect(ServiceRestart.answerWait == HeartbeatTiming.standard.grace)
    }
}
