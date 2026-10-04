import Foundation
import Testing
import LivepaperCore

struct WatchdogTests {
    struct Sample: Sendable {
        var before: Int
        var after: Int
        var expected: Int
        var attempt: Int = 0
    }

    static let rows: [Row<Sample, WatchdogVerdict>] = [
        // 60 pictures expected in the window.
        Row("every expected picture displayed is healthy", Sample(before: 100, after: 160, expected: 60), .healthy),
        Row("exactly half the expected pictures is healthy", Sample(before: 100, after: 130, expected: 60), .healthy),
        Row("one short of half is a stall", Sample(before: 100, after: 129, expected: 60), .flush),
        Row("no new pictures is a stall", Sample(before: 100, after: 100, expected: 60), .flush),
        Row("half of an odd expectation rounds against the stall", Sample(before: 0, after: 3, expected: 7), .flush),
        Row("a count that went backwards is a stall", Sample(before: 100, after: 4, expected: 60), .flush),
        Row("nothing expected is healthy", Sample(before: 100, after: 100, expected: 0), .healthy),

        // The ladder, by the number of recoveries already tried.
        Row("first recovery flushes", Sample(before: 0, after: 0, expected: 60, attempt: 0), .flush),
        Row("second recovery rebuilds the surface", Sample(before: 0, after: 0, expected: 60, attempt: 1), .rebuildSurface),
        Row("third recovery rebuilds the pipeline", Sample(before: 0, after: 0, expected: 60, attempt: 2), .rebuildPipeline),
        Row("fourth recovery restarts the agent", Sample(before: 0, after: 0, expected: 60, attempt: 3), .restartAgent),
        Row("the ladder ends at restarting the agent", Sample(before: 0, after: 0, expected: 60, attempt: 9), .restartAgent),
        Row("a negative attempt starts the ladder", Sample(before: 0, after: 0, expected: 60, attempt: -1), .flush),
        Row("healthy progress ignores the attempt", Sample(before: 0, after: 60, expected: 60, attempt: 3), .healthy),
    ]

    @Test(arguments: rows)
    func `judges progress in displayed pictures`(row: Row<Sample, WatchdogVerdict>) {
        let sample = row.input

        let verdict = judgeProgress(before: sample.before, after: sample.after, expected: sample.expected, attempt: sample.attempt)

        #expect(verdict == row.expected)
    }

    @Test func `recovery levels are ordered from mildest to harshest`() {
        #expect(RecoveryLevel.allCases == [.flush, .rebuildSurface, .rebuildPipeline, .restartAgent])
        #expect(RecoveryLevel.flush < RecoveryLevel.restartAgent)
    }
}

struct AgentRestartLimitTests {
    struct Request: Sendable {
        var last: Date?
        var now: Date
        var minimumGap: Duration = .seconds(600)
    }

    static let rows: [Row<Request, Bool>] = [
        Row("the first restart is always allowed", Request(last: nil, now: Moment.launch), true),
        Row("a second restart a second later is refused", Request(last: Moment.launch, now: Moment.after(1)), false),
        Row("a second restart just inside 10 minutes is refused", Request(last: Moment.launch, now: Moment.after(599.9)), false),
        Row("a restart exactly 10 minutes later is allowed", Request(last: Moment.launch, now: Moment.after(600)), true),
        Row("a restart an hour later is allowed", Request(last: Moment.launch, now: Moment.after(3600)), true),
        Row("the gap is the caller's", Request(last: Moment.launch, now: Moment.after(61), minimumGap: .seconds(60)), true),
        Row(
            "a clock that moved back does not open the gap early",
            Request(last: Moment.after(900), now: Moment.launch),
            false
        ),
    ]

    @Test(arguments: rows)
    func `limits agent restarts`(row: Row<Request, Bool>) {
        let allowed = allowAgentRestart(last: row.input.last, now: row.input.now, minimumGap: row.input.minimumGap)

        #expect(allowed == row.expected)
    }

    @Test func `the default gap is 10 minutes`() {
        #expect(agentRestartGap == .seconds(600))
        #expect(!allowAgentRestart(last: Moment.launch, now: Moment.after(599)))
        #expect(allowAgentRestart(last: Moment.launch, now: Moment.after(600)))
    }
}

struct HeartbeatJudgementTests {
    struct Observation: Sendable {
        var last: Date?
        var now: Date
    }

    // Standard timing: 20 s of grace after launch, a heartbeat counts for 15 s,
    // and the ladder climbs one level every 10 s after that.
    static let rows: [Row<Observation, RecoveryLevel?>] = [
        Row("silent at launch", Observation(last: nil, now: Moment.launch), nil),
        Row("silent through the grace period with no heartbeat", Observation(last: nil, now: Moment.after(19.9)), nil),
        Row("no heartbeat after the grace period starts the ladder", Observation(last: nil, now: Moment.after(20)), .flush),
        Row("still missing 10 s on, rebuild the surface", Observation(last: nil, now: Moment.after(30)), .rebuildSurface),
        Row("still missing 20 s on, rebuild the pipeline", Observation(last: nil, now: Moment.after(40)), .rebuildPipeline),
        Row("still missing 30 s on, restart the agent", Observation(last: nil, now: Moment.after(50)), .restartAgent),
        Row("it stays at restarting the agent", Observation(last: nil, now: Moment.after(5000)), .restartAgent),

        Row("quiet as soon as a heartbeat arrives", Observation(last: Moment.after(49), now: Moment.after(50)), nil),
        Row("a heartbeat 15 s old still counts", Observation(last: Moment.after(100), now: Moment.after(115)), nil),
        Row("a heartbeat that stopped starts the ladder", Observation(last: Moment.after(100), now: Moment.after(115.5)), .flush),
        Row("and it escalates while it stays missing", Observation(last: Moment.after(100), now: Moment.after(136)), .rebuildPipeline),
        Row(
            "an early heartbeat that stopped is still inside the grace period",
            Observation(last: Moment.after(1), now: Moment.after(18)),
            nil
        ),
        Row(
            "a heartbeat from before launch is no heartbeat",
            Observation(last: Moment.after(-5), now: Moment.after(20)),
            .flush
        ),
    ]

    @Test(arguments: rows)
    func `judges the heartbeat`(row: Row<Observation, RecoveryLevel?>) {
        let level = judgeHeartbeat(last: row.input.last, now: row.input.now, launchedAt: Moment.launch)

        #expect(level == row.expected)
    }

    @Test func `the extension sends a heartbeat more often than one lasts`() {
        #expect(HeartbeatTiming.standard.interval < HeartbeatTiming.standard.lifetime)
    }
}
