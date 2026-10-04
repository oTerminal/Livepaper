import Foundation
import LivepaperSoak
import Testing

/// The 4K60 budget against a measurement from `energy.sh`, line by line.
struct EnergyBudgetTests {
    /// Six 5 s samples of each process at a steady CPU and power.
    static func steady(_ phase: String, _ process: String, cpu: Double, power: Double, pid: Int = 1, memory: Int = 0) -> [EnergySample] {
        (0..<6).map {
            EnergySample(phase: phase, second: $0 * 5, process: process, pid: pid, cpu: cpu, power: power, memoryKilobytes: memory)
        }
    }

    /// The spike's own extension row, which the budget has 40 % headroom over.
    static let s2Run = steady("paused", "WallpaperExtension", cpu: 0, power: 0)
        + steady("paused", "VTDecoderXPCService", cpu: 0, power: 0)
        + steady("paused", "WindowServer", cpu: 22.1, power: 34.9)
        + steady("playing", "WallpaperExtension", cpu: 2.7, power: 3.6)
        + steady("playing", "VTDecoderXPCService", cpu: 3.5, power: 3.6, memory: 31_744)
        + steady("playing", "WindowServer", cpu: 45.1, power: 56.5)

    static func outcomes(_ samples: [EnergySample], watts: [WattSample]? = nil) -> [EnergyBudget.Check: EnergyBudget.Outcome] {
        let lines = EnergyBudget.s2.judge(EnergyMeasurement(samples: samples, watts: watts))
        return Dictionary(lines.map { ($0.check, $0.outcome) }, uniquingKeysWith: { first, _ in first })
    }

    @Test
    func `the spike's run is inside the budget, line for line`() {
        let outcomes = Self.outcomes(Self.s2Run)

        for check in [EnergyBudget.Check.extensionCPU, .extensionPower, .decoderCPU, .decoderPower, .windowServerOverPaused] {
            #expect(outcomes[check] == .pass, "\(check)")
        }
    }

    static let overruns: [Row<[EnergySample], EnergyBudget.Check>] = [
        Row(
            "the extension over 4 % CPU",
            s2Run.filter { !($0.phase == "playing" && $0.process == "WallpaperExtension") }
                + steady("playing", "WallpaperExtension", cpu: 4.2, power: 3.6),
            .extensionCPU
        ),
        Row(
            "the extension over a power score of 5",
            s2Run.filter { !($0.phase == "playing" && $0.process == "WallpaperExtension") }
                + steady("playing", "WallpaperExtension", cpu: 2.7, power: 5.3),
            .extensionPower
        ),
        Row(
            "two of the extension's decoders summed over 5 %",
            s2Run + steady("playing", "VTDecoderXPCService", cpu: 2.0, power: 1.0, pid: 2),
            .decoderCPU
        ),
        Row(
            "another client's decoder summed in over 5 %, as the spike summed them all",
            s2Run + steady("playing", "VTDecoderXPCService.others", cpu: 2.0, power: 1.0, pid: 9),
            .decoderCPU
        ),
        Row(
            "WindowServer 26 over its paused score",
            s2Run.filter { !($0.phase == "playing" && $0.process == "WindowServer") }
                + steady("playing", "WindowServer", cpu: 45.1, power: 60.9),
            .windowServerOverPaused
        ),
    ]

    @Test(arguments: overruns)
    func `a line over the budget fails, and only that line`(row: Row<[EnergySample], EnergyBudget.Check>) {
        let outcomes = Self.outcomes(row.input)

        #expect(outcomes[row.expected] == .fail)
        let others = [EnergyBudget.Check.extensionCPU, .extensionPower, .decoderCPU, .decoderPower, .windowServerOverPaused]
            .filter { $0 != row.expected }
        #expect(others.allSatisfy { outcomes[$0] == .pass })
    }

    /// One-second samples after the event at second 0: `back` is the first second each process is at its paused level.
    static func returning(
        _ phase: String, back: Int, decoderGoneFrom: Int? = nil, until last: Int = 10
    ) -> [EnergySample] {
        (0...last).flatMap { second -> [EnergySample] in
            let settled = second >= back
            var samples = [
                EnergySample(
                    phase: phase, second: second, process: "WallpaperExtension", pid: 1, cpu: settled ? 0 : 2.7, power: settled ? 0 : 3.6
                ),
                EnergySample(
                    phase: phase, second: second, process: "WindowServer", pid: 3, cpu: settled ? 22.1 : 45, power: settled ? 34.9 : 56
                ),
            ]
            if decoderGoneFrom.map({ second < $0 }) ?? true {
                samples.append(EnergySample(
                    phase: phase, second: second, process: "VTDecoderXPCService", pid: 2,
                    cpu: settled ? 0 : 3.5, power: settled ? 0 : 3.6, memoryKilobytes: settled ? 3_072 : 31_744
                ))
            }
            return samples
        }
    }

    /// Another client's decoder, busy every second of the phase: `energy.sh` names it `VTDecoderXPCService.others`.
    static func otherClient(_ phase: String) -> [EnergySample] {
        (0...10).map { EnergySample(phase: phase, second: $0, process: "VTDecoderXPCService.others", pid: 9, cpu: 3.5, power: 3.6) }
    }

    static let returns: [Row<[EnergySample], [EnergyBudget.Check: EnergyBudget.Outcome]>] = [
        Row(
            "covered, back in 3 s with the decoder kept",
            s2Run + returning("covered", back: 3),
            [.backWhenCovered: .pass, .decoderKeptWhenCovered: .pass]
        ),
        Row("covered, back only after 7 s", s2Run + returning("covered", back: 7), [.backWhenCovered: .fail]),
        Row("covered, never back", s2Run + returning("covered", back: 11), [.backWhenCovered: .fail]),
        Row(
            "covered, the decoder released",
            s2Run + returning("covered", back: 2, decoderGoneFrom: 2),
            [.backWhenCovered: .pass, .decoderKeptWhenCovered: .fail]
        ),
        Row(
            "display asleep, back and the decoder gone in 4 s",
            s2Run + returning("displayAsleep", back: 4, decoderGoneFrom: 4),
            [.backWhenAsleep: .pass, .decoderGoneWhenAsleep: .pass]
        ),
        Row(
            "display asleep, the decoder service still running, as it was found always to be",
            s2Run + returning("displayAsleep", back: 2),
            [.backWhenAsleep: .pass, .decoderGoneWhenAsleep: .recorded]
        ),
        Row(
            "display asleep, the decoder gone after 6 s",
            s2Run + returning("displayAsleep", back: 2, decoderGoneFrom: 6),
            [.decoderGoneWhenAsleep: .fail]
        ),
        Row("no covered or asleep phase", s2Run, [.backWhenCovered: .notMeasured, .backWhenAsleep: .notMeasured]),
        Row(
            "covered, the extension's decoder released while another client's runs on",
            s2Run + returning("covered", back: 2, decoderGoneFrom: 2) + otherClient("covered"),
            [.backWhenCovered: .pass, .decoderKeptWhenCovered: .fail]
        ),
        Row(
            "display asleep, the extension's decoder gone while another client's decodes on",
            s2Run + returning("displayAsleep", back: 4, decoderGoneFrom: 4) + otherClient("displayAsleep"),
            [.backWhenAsleep: .pass, .decoderGoneWhenAsleep: .pass]
        ),
    ]

    @Test(arguments: returns)
    func `all three back at paused levels within 5 s`(row: Row<[EnergySample], [EnergyBudget.Check: EnergyBudget.Outcome]>) {
        let outcomes = Self.outcomes(row.input)

        for (check, outcome) in row.expected {
            #expect(outcomes[check] == outcome, "\(check)")
        }
    }

    @Test
    func `a decoder service still running after display sleep is recorded with its footprint`() {
        let lines = EnergyBudget.s2.judge(EnergyMeasurement(samples: Self.s2Run + Self.returning("displayAsleep", back: 2), watts: nil))
        let line = lines.first { $0.check == .decoderGoneWhenAsleep }

        #expect(line?.measured == "running, 3.0 MB at the end, 31.0 MB playing")
    }

    @Test
    func `two samples of a process in one second are averaged, and its instances summed`() {
        let measurement = EnergyMeasurement(samples: [
            EnergySample(phase: "playing", second: 0, process: "VTDecoderXPCService", pid: 2, cpu: 2, power: 2),
            EnergySample(phase: "playing", second: 0, process: "VTDecoderXPCService", pid: 2, cpu: 4, power: 4),
            EnergySample(phase: "playing", second: 0, process: "VTDecoderXPCService", pid: 5, cpu: 1, power: 1),
        ], watts: nil)

        #expect(measurement.loads("VTDecoderXPCService", in: "playing")[0] == EnergyMeasurement.Load(cpu: 4, power: 4))
    }

    static let ceilings: [Row<EnergyBudget.Check, Bool>] = [
        Row("the extension's CPU", .extensionCPU, true),
        Row("the extension's power score", .extensionPower, true),
        Row("the decoders' CPU", .decoderCPU, true),
        Row("the decoders' power score", .decoderPower, true),
        Row("WindowServer over its paused score", .windowServerOverPaused, true),
        Row("the return after covering", .backWhenCovered, false),
        Row("the decoder kept while covered", .decoderKeptWhenCovered, false),
        Row("the scene's link after display sleep", .linkStoppedWhenAsleep, false),
        Row("the GPU after covering", .gpuBackWhenCovered, false),
        Row("idle", .idleApp, false),
        Row("watts", .watts, false),
    ]

    @Test(arguments: ceilings)
    func `the five ceilings are the budget's playing lines`(row: Row<EnergyBudget.Check, Bool>) {
        #expect(row.input.isCeiling == row.expected)
    }

    static func idle(_ phase: String, _ process: String, cpu: (Int) -> Double, count: Int = 60) -> [EnergySample] {
        (0..<count).map { EnergySample(phase: phase, second: $0 * 5, process: process, pid: 1, cpu: cpu($0), power: 0) }
    }

    static let idles: [Row<[EnergySample], EnergyBudget.Outcome>] = [
        Row("about 0 %", idle("idleApp", "Livepaper") { $0 == 7 ? 0.9 : 0.05 }, .pass),
        Row("one sample over 1 %", idle("idleApp", "Livepaper") { $0 == 7 ? 1.2 : 0 }, .fail),
        Row("a mean over 0.1 %", idle("idleApp", "Livepaper") { _ in 0.2 }, .fail),
        Row("fewer than 12 samples", idle("idleApp", "Livepaper", cpu: { _ in 0 }, count: 8), .inconclusive("8 samples of 12")),
        Row("not run", [], .notMeasured),
    ]

    @Test(arguments: idles)
    func `idle is a mean at or under 0.1 % and no sample over 1 %`(row: Row<[EnergySample], EnergyBudget.Outcome>) {
        #expect(Self.outcomes(row.input)[.idleApp] == row.expected)
    }

    @Test
    func `the extension idles with every display covered`() {
        let outcomes = Self.outcomes(Self.idle("idleExtension", "WallpaperExtension") { _ in 0 })

        #expect(outcomes[.idleExtension] == .pass)
    }

    @Test
    func `watts are recorded when powermetrics ran, and said to be missing when it did not`() {
        let watts = (0..<6).map { WattSample(phase: "playing", second: $0, combinedMilliwatts: 1_800, gpuMilliwatts: 400) }
        let lines = EnergyBudget.s2.judge(EnergyMeasurement(samples: Self.s2Run, watts: watts))
        let without = EnergyBudget.s2.judge(EnergyMeasurement(samples: Self.s2Run, watts: nil))

        #expect(lines.first { $0.check == .watts }?.outcome == .recorded)
        #expect(lines.first { $0.check == .watts }?.measured == "playing: 1.80 W, GPU 0.40 W")
        #expect(without.first { $0.check == .watts }?.outcome == .notMeasured)
    }

    @Test
    func `reads energy.sh's CSVs`() {
        let csv = """
        phase,second,process,pid,cpu,power,mem_kb
        playing,0,WallpaperExtension,711,2.7,3.6,53248
        playing,0,VTDecoderXPCService,812,1.5,1.6,31744
        playing,5,WindowServer,
        """
        let watts = """
        phase,second,combined_mw,gpu_mw
        playing,1,1800,400
        """
        let link = """
        phase,seconds
        covered,0.8
        displayAsleep,
        """

        #expect(EnergySample.read(csv: csv).samples.map(\.memoryKilobytes) == [53_248, 31_744])
        #expect(EnergySample.read(csv: csv).unreadRows == 1)
        #expect(
            WattSample.read(csv: watts).samples == [WattSample(phase: "playing", second: 1, combinedMilliwatts: 1_800, gpuMilliwatts: 400)]
        )
        #expect(LinkStop.read(csv: link).stops == [LinkStop(phase: "covered", seconds: 0.8)])
        #expect(LinkStop.read(csv: link).unreadRows == 1)
    }
}
