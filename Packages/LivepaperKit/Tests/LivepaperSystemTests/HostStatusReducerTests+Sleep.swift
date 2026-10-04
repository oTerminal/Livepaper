import Foundation
import LivepaperCore
import LivepaperSystem
import Testing

/// Sleep and wake: a wake starts a new grace period, however late or out of
/// order the sleep, the wake and the check that fell due in between arrive.
extension HostStatusReducerTests {
    @Test func `a wake before the first heartbeat still skips the levels nobody can receive`() {
        var script = HostScript()
        script.send(.systemWillSleep)
        script.send(.systemDidWake(at: Moment.after(1000)))

        script.runClock(until: 1100)

        #expect(script.steps == [
            .init(1_020_001, .skip(.flush)),
            .init(1_030_001, .skip(.rebuildSurface)),
            .init(1_030_001, .skip(.rebuildPipeline)),
            .init(1_030_001, .restart(.silence)),
        ])
    }

    @Test func `sleep stops the checks and a wake gives the extension a fresh grace period`() {
        var script = HostScript()
        script.heartbeats(from: 3, through: 98)

        script.send(.systemWillSleep)
        #expect(script.reducer.nextCheck == nil)
        script.send(.systemDidWake(at: Moment.after(4000)))

        #expect(script.reducer.status == .live)
        #expect(script.reducer.nextCheck.map(Moment.millisecond(of:)) == 4_020_001)
        script.runClock(until: 4025)
        #expect(script.steps == [.init(4_020_001, .post(.flush))])
    }

    @Test func `a heartbeat after a wake keeps the host live`() {
        var script = HostScript()
        script.heartbeats(from: 3, through: 98)
        script.send(.systemWillSleep)
        script.send(.systemDidWake(at: Moment.after(4000)))

        script.heartbeats(from: 4002, through: 4100)

        #expect(script.steps.isEmpty)
        #expect(script.reducer.status == .live)
    }

    @Test func `a tick while asleep does nothing`() {
        var script = HostScript()
        script.heartbeats(from: 3, through: 98)
        script.send(.systemWillSleep)

        script.send(.tick(at: Moment.after(4000)))

        #expect(script.steps.isEmpty)
        #expect(script.reducer.status == .live)
    }

    @Test func `a heartbeat while asleep counts as a wake`() {
        var script = HostScript()
        script.heartbeats(from: 3, through: 98)
        script.send(.systemWillSleep)

        script.heartbeat(at: 4000)

        #expect(script.reducer.nextCheck.map(Moment.millisecond(of:)) == 4_020_001)
    }

    // The heartbeats stop at 98 s as the lid closes, so the check is due at 113 s.
    // The lid opens at 4000 s, and what reaches the reducer then comes in any order.
    static let wakeRows: [Row<[HostEvent], [HostScript.Step]>] = [
        Row(
            "the check due in the sleep fires at the wake, before the wake is heard",
            [.tick(at: Moment.after(4000)), .systemDidWake(at: Moment.after(4000.004))],
            [.init(4_020_005, .post(.flush))]
        ),
        Row(
            "the wake is heard first, then the check due in the sleep",
            [.systemDidWake(at: Moment.after(4000)), .tick(at: Moment.after(4000.004))],
            [.init(4_020_001, .post(.flush))]
        ),
        Row("neither the sleep nor the wake is heard", [.tick(at: Moment.after(4000))], [.init(4_020_001, .post(.flush))]),
        Row(
            "the sleep and the wake are heard only after the check",
            [.tick(at: Moment.after(4000)), .systemWillSleep, .systemDidWake(at: Moment.after(4000.004))],
            [.init(4_020_005, .post(.flush))]
        ),
        Row(
            "a heartbeat at the wake, before the check",
            [.heartbeat(Heartbeat(generation: 1, flags: .desktopSurfaceAcquired), at: Moment.after(4000))],
            [.init(4_020_001, .post(.flush))]
        ),
    ]

    @Test(arguments: wakeRows)
    func `a check the Mac slept through starts a new grace period, whatever order the wake comes in`(
        row: Row<[HostEvent], [HostScript.Step]>
    ) {
        var script = HostScript()
        script.heartbeats(from: 3, through: 98)

        for event in row.input { script.send(event) }
        script.runClock(until: 4025)

        #expect(script.steps == row.expected)
    }

    /// The rest of the ladder, from the second level on, when the first check comes at 113 s or a little after.
    static let restOfLadder: [HostScript.Step] = [
        .init(123_001, .post(.rebuildSurface)),
        .init(133_001, .post(.rebuildPipeline)),
        .init(143_001, .restart(.silence)),
    ]

    static let awakeRows: [Row<[HostEvent], [HostScript.Step]>] = [
        Row("an ordinary long silence, each check on time", [], [.init(113_001, .post(.flush))] + restOfLadder),
        Row(
            "the first check four seconds late, the Mac awake",
            [.tick(at: Moment.after(117))],
            [.init(117_000, .post(.flush))] + restOfLadder
        ),
    ]

    @Test(arguments: awakeRows)
    func `silence on an awake Mac still climbs the ladder`(row: Row<[HostEvent], [HostScript.Step]>) {
        var script = HostScript()
        script.heartbeats(from: 3, through: 98)

        for event in row.input { script.send(event) }
        script.runClock(until: 4040)

        #expect(script.steps == row.expected)
    }
}
