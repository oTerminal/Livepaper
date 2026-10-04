import Foundation
import LivepaperCore
import LivepaperSystem
import Testing

struct ConditionsFolderTests {
    struct Timed: Sendable {
        var second: Double
        var event: SensorEvent
    }

    static let one = DisplayIdentity.numbered(1)
    static let two = DisplayIdentity.numbered(2)
    static let rulesOff = PauseRules(whenDesktopCovered: false, whenDisplayAsleepOrLocked: false, inLowPowerMode: false, onBattery: false)
    static let lowPower = PowerState(lowPowerMode: true, onBattery: false)

    static func at(_ second: Double, _ event: SensorEvent) -> Timed {
        Timed(second: second, event: event)
    }

    static func sensed(
        _ second: Double,
        covered: Set<DisplayIdentity> = [],
        asleep: Set<DisplayIdentity> = [],
        locked: Bool = false,
        lowPowerMode: Bool = false,
        onBattery: Bool = false
    ) -> SensedConditions {
        SensedConditions(
            sensedAt: Moment.after(second),
            coveredDisplays: covered,
            asleepDisplays: asleep,
            locked: locked,
            lowPowerMode: lowPowerMode,
            onBattery: onBattery
        )
    }

    static let rows: [Row<[Timed], [SensedConditions]>] = [
        Row("a change gives conditions", [at(0, .displays([one])), at(1, .covered([one]))], [sensed(1, covered: [one])]),
        Row(
            "the same value again gives nothing",
            [at(0, .displays([one])), at(1, .covered([one])), at(2, .covered([one]))],
            [sensed(1, covered: [one])]
        ),
        Row(
            "each change gives its own conditions, with everything sensed so far",
            [at(0, .displays([one])), at(1, .locked(true)), at(2, .power(lowPower))],
            [sensed(1, locked: true), sensed(2, locked: true, lowPowerMode: true)]
        ),
        Row(
            "first values that match nothing sensed give nothing",
            [at(0, .displays([one])), at(1, .covered([])), at(1, .asleep([])), at(1, .locked(false)), at(1, .power(PowerState()))],
            []
        ),
        Row("connected displays alone give nothing", [at(0, .displays([one])), at(1, .displays([one, two]))], []),

        // Refreshing while a rule would pause a display.
        Row(
            "a covered display is sensed again at half the expiry",
            [at(0, .displays([one])), at(1, .covered([one])), at(16, .tick)],
            [sensed(1, covered: [one]), sensed(16, covered: [one])]
        ),
        Row(
            "not before it is due",
            [at(0, .displays([one])), at(1, .covered([one])), at(15.5, .tick)],
            [sensed(1, covered: [one])]
        ),
        Row(
            "and again half an expiry after the refresh",
            [at(0, .displays([one])), at(1, .covered([one])), at(16, .tick), at(30, .tick), at(31, .tick)],
            [sensed(1, covered: [one]), sensed(16, covered: [one]), sensed(31, covered: [one])]
        ),
        Row(
            "a sleeping display is refreshed",
            [at(0, .displays([one])), at(1, .asleep([one])), at(16, .tick)],
            [sensed(1, asleep: [one]), sensed(16, asleep: [one])]
        ),
        Row(
            "Low Power Mode is refreshed",
            [at(0, .displays([one])), at(1, .power(lowPower)), at(16, .tick)],
            [sensed(1, lowPowerMode: true), sensed(16, lowPowerMode: true)]
        ),

        // No refresh while nothing would pause.
        Row(
            "a lock is not refreshed, the extension plays on the lock screen",
            [at(0, .displays([one])), at(1, .locked(true)), at(16, .tick), at(100, .tick)],
            [sensed(1, locked: true)]
        ),
        Row(
            "battery is not refreshed while its rule is off, as it ships",
            [at(0, .displays([one])), at(1, .power(PowerState(lowPowerMode: false, onBattery: true))), at(16, .tick)],
            [sensed(1, onBattery: true)]
        ),
        Row(
            "a covered display is not refreshed while its rule is off",
            [at(0, .rules(rulesOff)), at(0, .displays([one])), at(1, .covered([one])), at(16, .tick)],
            [sensed(1, covered: [one])]
        ),
        Row(
            "no display connected, nothing to pause",
            [at(1, .power(lowPower)), at(16, .tick)],
            [sensed(1, lowPowerMode: true)]
        ),
        Row(
            "uncovering gives one change and then no refresh",
            [at(0, .displays([one])), at(1, .covered([one])), at(5, .covered([])), at(20, .tick), at(40, .tick)],
            [sensed(1, covered: [one]), sensed(5)]
        ),

        // What changes whether anything would pause, without changing what is sensed.
        Row(
            "switching a rule on refreshes stale conditions at once",
            [at(0, .rules(rulesOff)), at(0, .displays([one])), at(1, .covered([one])), at(100, .rules(PauseRules()))],
            [sensed(1, covered: [one]), sensed(100, covered: [one])]
        ),
        Row(
            "switching a rule off gives nothing and stops the refresh",
            [at(0, .displays([one])), at(1, .covered([one])), at(5, .rules(rulesOff)), at(16, .tick)],
            [sensed(1, covered: [one])]
        ),
        Row(
            "a display connecting while Low Power Mode is on refreshes stale conditions",
            [at(1, .power(lowPower)), at(100, .displays([one]))],
            [sensed(1, lowPowerMode: true), sensed(100, lowPowerMode: true)]
        ),
    ]

    @Test(arguments: rows)
    func `folds sensor events into sensed conditions`(row: Row<[Timed], [SensedConditions]>) {
        var folder = ConditionsFolder()

        let emitted = row.input.compactMap { folder.fold($0.event, at: Moment.after($0.second)) }

        #expect(emitted == row.expected)
    }

    @Test func `the next refresh is at half the expiry while something would pause, and none otherwise`() {
        var folder = ConditionsFolder()
        _ = folder.fold(.displays([Self.one]), at: Moment.launch)
        #expect(folder.nextRefresh == nil)

        _ = folder.fold(.covered([Self.one]), at: Moment.after(1))
        #expect(folder.nextRefresh.map(Moment.millisecond(of:)) == 16_000)

        _ = folder.fold(.covered([]), at: Moment.after(5))
        #expect(folder.nextRefresh == nil)
    }

    @Test func `the latest conditions are kept`() {
        var folder = ConditionsFolder()
        _ = folder.fold(.displays([Self.one]), at: Moment.launch)
        _ = folder.fold(.locked(true), at: Moment.after(1))

        #expect(folder.latest == Self.sensed(1, locked: true))
    }
}
