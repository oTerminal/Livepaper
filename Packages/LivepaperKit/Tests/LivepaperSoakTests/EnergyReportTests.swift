import Foundation
import LivepaperSoak
import Testing

struct EnergyReportTests {
    @Test
    func `a video run is held to the budget line by line`() {
        let report = EnergyReport(measurement: EnergyMeasurement(samples: EnergyBudgetTests.s2Run, watts: nil), kind: .video)

        #expect(report.markdown.contains("| Extension CPU | 2.7 % | at most 4.0 % | pass |"))
        #expect(report.markdown.contains("| WindowServer power over its paused score | 21.6 | at most 25.0 | pass |"))
        #expect(report.markdown.contains(
            "| Watts, from powermetrics | none: powermetrics must be run as the superuser | recorded | not measured |"
        ))
    }

    @Test
    func `a scene run is a baseline, first measured here`() {
        let report = EnergyReport(measurement: EnergyMeasurement(samples: EnergyBudgetTests.s2Run, watts: nil), kind: .scene)

        #expect(report.markdown.contains("| Extension CPU | 2.7 % | baseline | recorded |"))
        #expect(!report.markdown.contains("| pass |"))
    }

    @Test
    func `each phase's means, per process, other clients' decoders apart`() {
        let others = EnergyBudgetTests.steady("playing", "VTDecoderXPCService.others", cpu: 1.2, power: 0.8, pid: 9)
        let report = EnergyReport(measurement: EnergyMeasurement(samples: EnergyBudgetTests.s2Run + others, watts: nil), kind: .video)

        #expect(report.markdown.contains(
            "| Phase | WallpaperExtension | VTDecoderXPCService | VTDecoderXPCService.others | WindowServer | Livepaper |"
        ))
        #expect(report.markdown.contains("| playing | 2.7 % / 3.6 | 3.5 % / 3.6 | 1.2 % / 0.8 | 45.1 % / 56.5 |  |"))
        #expect(report.markdown.contains("| paused | 0.0 % / 0.0 | 0.0 % / 0.0 |  | 22.1 % / 34.9 |  |"))
    }

    // MARK: A scene after covering and display sleep

    /// The spike run's phases with a scene's covering and display sleep after them: no decoder, each process back at `back`.
    static func sceneRun(back: Int = 2) -> [EnergySample] {
        EnergyBudgetTests.s2Run
            + EnergyBudgetTests.returning("covered", back: back, decoderGoneFrom: 0)
            + EnergyBudgetTests.returning("displayAsleep", back: back, decoderGoneFrom: 0)
    }

    static func scene(_ samples: [EnergySample], watts: [WattSample]? = nil, links: [LinkStop]? = nil) -> EnergyReport {
        EnergyReport(measurement: EnergyMeasurement(samples: samples, watts: watts, links: links), kind: .scene)
    }

    static func outcomes(_ report: EnergyReport) -> [EnergyBudget.Check: EnergyBudget.Outcome] {
        Dictionary(report.lines.map { ($0.check, $0.outcome) }, uniquingKeysWith: { first, _ in first })
    }

    @Test
    func `a scene has no decoder, so no kept or gone line, and a video no GPU or link line`() {
        let decoderLines: Set<EnergyBudget.Check> = [.decoderKeptWhenCovered, .decoderGoneWhenAsleep]
        let sceneLines: Set<EnergyBudget.Check> = [.gpuBackWhenCovered, .gpuBackWhenAsleep, .linkStoppedWhenCovered, .linkStoppedWhenAsleep]
        let scene = Self.scene(Self.sceneRun())
        let video = EnergyReport(measurement: EnergyMeasurement(samples: Self.sceneRun()), kind: .video)

        #expect(Set(scene.lines.map(\.check)).isDisjoint(with: decoderLines))
        #expect(Set(scene.lines.map(\.check)).isSuperset(of: sceneLines))
        #expect(Set(video.lines.map(\.check)).isDisjoint(with: sceneLines))
        #expect(Set(video.lines.map(\.check)).isSuperset(of: decoderLines))
    }

    /// powermetrics' GPU while paused: 300 mW a second, one second at 320.
    static let pausedGPU = (0..<30).map {
        WattSample(phase: "paused", second: $0, combinedMilliwatts: 900, gpuMilliwatts: $0 == 12 ? 320 : 300)
    }

    /// The GPU after the event at second 0: drawing at 900 mW until `back`, then at 310, under the highest paused sample.
    static func gpu(_ phase: String, back: Int) -> [WattSample] {
        (0...10).map { WattSample(phase: phase, second: $0, combinedMilliwatts: 1_500, gpuMilliwatts: $0 >= back ? 310 : 900) }
    }

    static let gpuReturns: [Row<[WattSample]?, [EnergyBudget.Check: EnergyBudget.Outcome]>] = [
        Row(
            "back at the highest paused sample in 3 s after covering, 1 s after display sleep",
            pausedGPU + gpu("covered", back: 3) + gpu("displayAsleep", back: 1),
            [.gpuBackWhenCovered: .pass, .gpuBackWhenAsleep: .pass]
        ),
        Row(
            "back only after 7 s when covered",
            pausedGPU + gpu("covered", back: 7) + gpu("displayAsleep", back: 1),
            [.gpuBackWhenCovered: .fail, .gpuBackWhenAsleep: .pass]
        ),
        Row(
            "never back while the display sleeps",
            pausedGPU + gpu("covered", back: 0) + gpu("displayAsleep", back: 11),
            [.gpuBackWhenCovered: .pass, .gpuBackWhenAsleep: .fail]
        ),
        Row("no watts: powermetrics did not run", nil, [.gpuBackWhenCovered: .notMeasured, .gpuBackWhenAsleep: .notMeasured]),
        Row(
            "no paused watts to be back at",
            gpu("covered", back: 0) + gpu("displayAsleep", back: 0),
            [.gpuBackWhenCovered: .notMeasured, .gpuBackWhenAsleep: .notMeasured]
        ),
    ]

    @Test(arguments: gpuReturns)
    func `a scene's GPU back at paused levels within 5 s`(row: Row<[WattSample]?, [EnergyBudget.Check: EnergyBudget.Outcome]>) {
        let outcomes = Self.outcomes(Self.scene(Self.sceneRun(), watts: row.input))

        for (check, outcome) in row.expected {
            #expect(outcomes[check] == outcome, "\(check)")
        }
    }

    @Test
    func `a scene's GPU line says when it was back, or that it was not`() {
        let report = Self.scene(Self.sceneRun(), watts: Self.pausedGPU + Self.gpu("covered", back: 3) + Self.gpu("displayAsleep", back: 11))

        #expect(report.markdown.contains("| GPU at paused levels after covering | 3 s | within 5 s | pass |"))
        #expect(report.markdown.contains("| GPU at paused levels after display sleep | not back in 10 s | within 5 s | fail |"))
    }

    static let linkStops: [Row<[LinkStop]?, [EnergyBudget.Check: EnergyBudget.Outcome]>] = [
        Row(
            "stopped 0.8 s after covering and 1.4 s after display sleep",
            [LinkStop(phase: "covered", seconds: 0.8), LinkStop(phase: "displayAsleep", seconds: 1.4)],
            [.linkStoppedWhenCovered: .pass, .linkStoppedWhenAsleep: .pass]
        ),
        Row(
            "stopped 6.2 s after covering",
            [LinkStop(phase: "covered", seconds: 6.2), LinkStop(phase: "displayAsleep", seconds: 1.4)],
            [.linkStoppedWhenCovered: .fail, .linkStoppedWhenAsleep: .pass]
        ),
        Row(
            "no stop logged after display sleep",
            [LinkStop(phase: "covered", seconds: 0.8)],
            [.linkStoppedWhenCovered: .pass, .linkStoppedWhenAsleep: .fail]
        ),
        Row("no link.csv given", nil, [.linkStoppedWhenCovered: .notMeasured, .linkStoppedWhenAsleep: .notMeasured]),
    ]

    @Test(arguments: linkStops)
    func `a scene's link stopped within 5 s of covering or display sleep`(
        row: Row<[LinkStop]?, [EnergyBudget.Check: EnergyBudget.Outcome]>
    ) {
        let outcomes = Self.outcomes(Self.scene(Self.sceneRun(), links: row.input))

        for (check, outcome) in row.expected {
            #expect(outcomes[check] == outcome, "\(check)")
        }
    }

    @Test
    func `a scene's link line says when it stopped, or that the log had no stop`() {
        let report = Self.scene(Self.sceneRun(), links: [LinkStop(phase: "covered", seconds: 0.8)])

        #expect(report.markdown.contains("| The scene's link stopped after covering | at 0.8 s | within 5 s | pass |"))
        #expect(report.markdown.contains(
            "| The scene's link stopped after display sleep | no stop in the extension's log | within 5 s | fail |"
        ))
    }

    @Test
    func `a scene not covered or put to sleep has its return lines not measured, link.csv or not`() {
        let outcomes = Self.outcomes(Self.scene(EnergyBudgetTests.s2Run, watts: Self.pausedGPU, links: []))

        #expect(outcomes[.linkStoppedWhenCovered] == .notMeasured)
        #expect(outcomes[.gpuBackWhenAsleep] == .notMeasured)
    }
}
