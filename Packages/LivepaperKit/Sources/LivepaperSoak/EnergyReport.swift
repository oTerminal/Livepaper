import Foundation

/// `energy.sh`'s report: the budget line by line for a video, the same numbers as
/// a baseline for a scene (a scene's cost was left unmeasured), and each phase's means.
public struct EnergyReport: Sendable {
    public enum Kind: Sendable {
        case video
        /// First measured here: recorded, held to nothing but the return to paused levels
        /// and the display link stopping. A scene has no decoder, so nothing is said of one.
        case scene
    }

    public let lines: [EnergyBudget.Line]
    public let markdown: String

    public init(measurement: EnergyMeasurement, kind: Kind, unreadRows: Int = 0, budget: EnergyBudget = .s2) {
        lines = budget.judge(measurement, kind: kind).map { line in
            guard kind == .scene, line.check.isCeiling, line.outcome != .notMeasured else { return line }
            var baseline = line
            baseline.limit = "baseline"
            baseline.outcome = .recorded
            return baseline
        }

        var text = "# Energy, \(kind == .video ? "a video" : "a scene")\n\n"
        text += "top's CPU and power score (unitless energy impact), six 5 s samples after a 15 s warm-up; "
        text += "one-second samples after covering and display sleep."
        if kind == .scene {
            text += " The GPU is powermetrics', the link's stop the extension's first `stopped drawing at` line after each (link.csv)."
        }
        text += "\n\n| Measurement | Measured | Limit | Outcome |\n|---|---|---|---|\n"
        for line in lines {
            text += "| \(line.name) | \(line.measured) | \(line.limit) | \(Self.words(line.outcome)) |\n"
        }
        text += "\n## Means by phase\n\nCPU / power score, each process's instances summed. "
        text += "\(EnergyBudget.decoderProcess) is the extension's own, \(EnergyBudget.otherDecodersProcess) every other client's.\n\n"
        let processes = [
            EnergyBudget.extensionProcess, EnergyBudget.decoderProcess, EnergyBudget.otherDecodersProcess,
            EnergyBudget.windowServer, EnergyBudget.appProcess,
        ]
        text += "| Phase | " + processes.joined(separator: " | ") + " |\n|---|" + processes.map { _ in "---|" }.joined() + "\n"
        for phase in measurement.phases {
            let means = processes.map { process in
                measurement.loads(process, in: phase).isEmpty ? ""
                    : measurement.mean(process, in: phase).map { String(format: "%.1f %% / %.1f", $0.cpu, $0.power) } ?? ""
            }
            text += "| \(phase) | " + means.joined(separator: " | ") + " |\n"
        }
        if unreadRows > 0 { text += "\n\(counted(unreadRows, "row")) of energy.csv could not be read.\n" }
        markdown = text
    }

    private static func words(_ outcome: EnergyBudget.Outcome) -> String {
        switch outcome {
        case .pass: "pass"
        case .fail: "fail"
        case .recorded: "recorded"
        case .notMeasured: "not measured"
        case .inconclusive(let reason): "inconclusive: \(reason)"
        }
    }
}
