import Foundation
import LivepaperCore
import LivepaperSystem
import LivepaperTestSupport
import os
import Testing

// Some tests wait on what the sensors hand on; one that never comes fails the test instead of hanging the run.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ConditionsSensingTests {
    static let one = DisplayIdentity.numbered(1)
    static let builtIn = ConnectedDisplay(
        identity: one,
        displayID: 1,
        pixelSize: Size(width: 3600, height: 2338),
        frame: Rect(origin: Point(x: 0, y: 0), size: Size(width: 1800, height: 1169))
    )

    let clock = ManualWallClock()
    let displays = FakeDisplaySensor([builtIn])
    let power = FakePowerSensor(PowerState())
    let lock = FakeLockSensor(false)
    let displaySleep = FakeDisplaySleepSensor([])
    let covered = FakeCoveredDisplaySensor([])
    let handedOn: AsyncStream<SensedConditions>
    let sensing: ConditionsSensing

    init() {
        let (handedOn, continuation) = AsyncStream.makeStream(of: SensedConditions.self)
        self.handedOn = handedOn
        sensing = ConditionsSensing(
            rules: PauseRules(),
            displays: displays,
            power: power,
            lock: lock,
            displaySleep: displaySleep,
            covered: covered,
            clock: clock,
            logger: Logger(subsystem: "app.livepaper.tests", category: SensingLog.category)
        ) { conditions in
            continuation.yield(conditions)
        }
    }

    /// Lets the owner's tasks run until `condition` holds, or gives up.
    func settle(until condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
    }

    @Test func `a change from a sensor is handed on, and nothing before it`() async {
        sensing.start()

        covered.send([Self.one])

        var conditions = handedOn.makeAsyncIterator()
        #expect(await conditions.next() == SensedConditions(sensedAt: Moment.launch, coveredDisplays: [Self.one]))
    }

    @Test func `a condition already sensed at the start is handed on`() async {
        lock.send(true)

        sensing.start()

        var conditions = handedOn.makeAsyncIterator()
        #expect(await conditions.next() == SensedConditions(sensedAt: Moment.launch, locked: true))
    }

    @Test func `conditions that pause a display are handed on again at half the expiry`() async {
        sensing.start()
        covered.send([Self.one])
        var conditions = handedOn.makeAsyncIterator()
        _ = await conditions.next()
        #expect(clock.scheduled.map(Moment.millisecond(of:)) == [15_000])

        clock.advance(toSecond: 15)

        #expect(await conditions.next() == SensedConditions(sensedAt: Moment.after(15), coveredDisplays: [Self.one]))
        #expect(clock.scheduled.map(Moment.millisecond(of:)) == [30_000])
    }

    @Test func `nothing is scheduled while nothing would pause`() async {
        sensing.start()
        lock.send(true)
        var conditions = handedOn.makeAsyncIterator()
        _ = await conditions.next()

        #expect(clock.scheduled.isEmpty)
    }

    @Test func `switching a rule on hands the stale conditions on again`() async {
        sensing.rules = PauseRules(whenDesktopCovered: false)
        sensing.start()
        covered.send([Self.one])
        var conditions = handedOn.makeAsyncIterator()
        _ = await conditions.next()
        #expect(clock.scheduled.isEmpty)
        clock.advance(toSecond: 100)

        sensing.rules = PauseRules()

        #expect(await conditions.next() == SensedConditions(sensedAt: Moment.after(100), coveredDisplays: [Self.one]))
    }

    @Test func `the covered-display sensor is told whether covering pauses, and told again when the rule changes`() {
        #expect(covered.coveringPauses)

        sensing.rules = PauseRules(whenDesktopCovered: false)
        #expect(covered.coveringPauses == false)
        sensing.rules = PauseRules()

        #expect(covered.coveringPauses)
    }

    @Test func `the connected displays are kept for whoever needs them`() async {
        sensing.start()

        await settle { sensing.connectedDisplays == [Self.builtIn] }

        #expect(sensing.connectedDisplays == [Self.builtIn])
    }

    @Test func `stopping stops reading the sensors and the refresh`() async {
        sensing.start()
        covered.send([Self.one])
        var conditions = handedOn.makeAsyncIterator()
        _ = await conditions.next()

        sensing.stop()
        await settle { readers == [0, 0, 0, 0, 0] }

        #expect(readers == [0, 0, 0, 0, 0])
        #expect(clock.scheduled.isEmpty)
    }

    var readers: [Int] {
        [displays.readerCount, power.readerCount, lock.readerCount, displaySleep.readerCount, covered.readerCount]
    }
}
