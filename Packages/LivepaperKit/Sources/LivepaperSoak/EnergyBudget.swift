import Foundation

/// The energy budget for one display playing 4K60 HEVC with the desktop visible,
/// and the idle rows, each held to a measurement line by line.
public struct EnergyBudget: Sendable {
    public enum Check: Sendable {
        case extensionCPU
        case extensionPower
        case decoderCPU
        case decoderPower
        case windowServerOverPaused
        case backWhenCovered
        case decoderKeptWhenCovered
        case gpuBackWhenCovered
        case linkStoppedWhenCovered
        case backWhenAsleep
        case decoderGoneWhenAsleep
        case gpuBackWhenAsleep
        case linkStoppedWhenAsleep
        case idleApp
        case idleExtension
        case watts

        /// The five ceilings on the playing phase, which a scene's run records as a baseline.
        public var isCeiling: Bool {
            switch self {
            case .extensionCPU, .extensionPower, .decoderCPU, .decoderPower, .windowServerOverPaused: true
            case .backWhenCovered, .decoderKeptWhenCovered, .gpuBackWhenCovered, .linkStoppedWhenCovered, .backWhenAsleep,
                 .decoderGoneWhenAsleep, .gpuBackWhenAsleep, .linkStoppedWhenAsleep, .idleApp, .idleExtension, .watts: false
            }
        }
    }

    public enum Outcome: Equatable, Sendable {
        case pass
        case fail
        /// A number kept as a baseline, held to nothing.
        case recorded
        case notMeasured
        case inconclusive(String)
    }

    public struct Line: Equatable, Sendable {
        public var check: Check
        public var name: String
        public var measured: String
        public var limit: String
        public var outcome: Outcome
    }

    public static let extensionProcess = "WallpaperExtension"
    /// The extension's own `VTDecoderXPCService`, the one in its launchd domain.
    public static let decoderProcess = "VTDecoderXPCService"
    /// Every other client's `VTDecoderXPCService`: summed into the two decoder ceilings, as the spike summed
    /// them all, and into nothing else, where they would hide the extension's leaving.
    public static let otherDecodersProcess = "VTDecoderXPCService.others"
    public static let windowServer = "WindowServer"
    public static let appProcess = "Livepaper"

    public var extensionCPU: Double
    public var extensionPower: Double
    public var decoderCPU: Double
    public var decoderPower: Double
    public var windowServerOverPaused: Double
    public var returnSeconds: Int
    public var idleMeanCPU: Double
    public var idlePeakCPU: Double
    public var idleSamples: Int

    /// The spike's numbers, and a reading of "about 0 %" for idle.
    public static let s2 = EnergyBudget(
        extensionCPU: 4, extensionPower: 5, decoderCPU: 5, decoderPower: 5, windowServerOverPaused: 25, returnSeconds: 5,
        idleMeanCPU: 0.1, idlePeakCPU: 1, idleSamples: 12
    )

    /// Every line, in the report's order. A scene has no decoder, so after covering and display sleep
    /// its lines are the GPU's and the display link's where a video's are the decoder's.
    public func judge(_ measurement: EnergyMeasurement, kind: EnergyReport.Kind = .video) -> [Line] {
        typealias Phase = EnergyMeasurement.Phase
        let playingExtension = measurement.mean(Self.extensionProcess, in: Phase.playing)
        let playingDecoders = measurement.mean([Self.decoderProcess, Self.otherDecodersProcess], in: Phase.playing)
        var lines = [
            ceiling(.extensionCPU, "Extension CPU", playingExtension?.cpu, extensionCPU, unit: " %"),
            ceiling(.extensionPower, "Extension power", playingExtension?.power, extensionPower),
            ceiling(.decoderCPU, "VTDecoderXPCService CPU, summed", playingDecoders?.cpu, decoderCPU, unit: " %"),
            ceiling(.decoderPower, "VTDecoderXPCService power, summed", playingDecoders?.power, decoderPower),
        ]
        let overPaused = measurement.mean(Self.windowServer, in: Phase.playing).flatMap { playing in
            measurement.mean(Self.windowServer, in: Phase.paused).map { playing.power - $0.power }
        }
        lines.append(ceiling(.windowServerOverPaused, "WindowServer power over its paused score", overPaused, windowServerOverPaused))
        lines += returnLines(measurement, after: .covering, kind: kind)
        lines += returnLines(measurement, after: .displaySleep, kind: kind)
        lines.append(idle(.idleApp, "The app idle, popover and window closed", measurement, process: Self.appProcess, phase: Phase.idleApp))
        lines.append(idle(
            .idleExtension, "The extension idle, every display covered", measurement,
            process: Self.extensionProcess, phase: Phase.idleExtension
        ))
        lines.append(watts(measurement))
        return lines
    }

    private func ceiling(_ check: Check, _ name: String, _ value: Double?, _ limit: Double, unit: String = "") -> Line {
        guard let value else {
            return Line(check: check, name: name, measured: "not measured", limit: "\(format(limit))\(unit)", outcome: .notMeasured)
        }
        return Line(
            check: check, name: name, measured: "\(format(value))\(unit)", limit: "at most \(format(limit))\(unit)",
            outcome: value <= limit ? .pass : .fail
        )
    }

    private func idle(_ check: Check, _ name: String, _ measurement: EnergyMeasurement, process: String, phase: String) -> Line {
        let limit = "mean at most \(format(idleMeanCPU)) %, no sample over \(format(idlePeakCPU)) %"
        let seconds = measurement.seconds(in: phase)
        guard !seconds.isEmpty else { return Line(check: check, name: name, measured: "not measured", limit: limit, outcome: .notMeasured) }
        let loads = measurement.loads(process, in: phase)
        let cpu = seconds.map { loads[$0]?.cpu ?? 0 }
        let mean = cpu.reduce(0, +) / Double(cpu.count)
        let peak = cpu.max() ?? 0
        let measured = "mean \(format(mean, digits: 2)) %, peak \(format(peak)) %, \(cpu.count) samples"
        guard cpu.count >= idleSamples else {
            return Line(
                check: check, name: name, measured: measured, limit: limit, outcome: .inconclusive("\(cpu.count) samples of \(idleSamples)")
            )
        }
        return Line(
            check: check, name: name, measured: measured, limit: limit, outcome: mean <= idleMeanCPU && peak <= idlePeakCPU ? .pass : .fail
        )
    }

    private func watts(_ measurement: EnergyMeasurement) -> Line {
        let name = "Watts, from powermetrics"
        guard let watts = measurement.watts, !watts.isEmpty else {
            return Line(
                check: .watts, name: name, measured: "none: powermetrics must be run as the superuser",
                limit: "recorded", outcome: .notMeasured
            )
        }
        var phases: [String] = []
        for sample in watts where !phases.contains(sample.phase) { phases.append(sample.phase) }
        let measured = phases.map { phase in
            let own = watts.filter { $0.phase == phase }
            let combined = own.map(\.combinedMilliwatts).reduce(0, +) / Double(own.count) / 1_000
            let gpu = own.map(\.gpuMilliwatts).reduce(0, +) / Double(own.count) / 1_000
            return "\(phase): \(format(combined, digits: 2)) W, GPU \(format(gpu, digits: 2)) W"
        }
        return Line(check: .watts, name: name, measured: measured.joined(separator: "; "), limit: "recorded", outcome: .recorded)
    }

    private func format(_ value: Double, digits: Int = 1) -> String {
        String(format: "%.\(digits)f", value)
    }
}

// MARK: After covering and display sleep

extension EnergyBudget {
    /// Covering or display sleep: its phase in `energy.csv`, and its lines.
    private struct Event {
        let phase: String
        /// How its lines name it: "… after covering".
        let words: String
        let back: Check
        let decoder: Check
        let gpu: Check
        let link: Check

        static let covering = Event(
            phase: EnergyMeasurement.Phase.covered, words: "covering",
            back: .backWhenCovered, decoder: .decoderKeptWhenCovered, gpu: .gpuBackWhenCovered, link: .linkStoppedWhenCovered
        )
        static let displaySleep = Event(
            phase: EnergyMeasurement.Phase.displayAsleep, words: "display sleep",
            back: .backWhenAsleep, decoder: .decoderGoneWhenAsleep, gpu: .gpuBackWhenAsleep, link: .linkStoppedWhenAsleep
        )
    }

    /// Within `returnSeconds` of the event: the three processes back at paused levels, and for a video
    /// the extension's decoder kept or gone, for a scene the GPU back at paused levels and its link stopped.
    /// A phase that was not run is not measured.
    private func returnLines(_ measurement: EnergyMeasurement, after event: Event, kind: EnergyReport.Kind) -> [Line] {
        let seconds = measurement.seconds(in: event.phase)
        let back = processesBack(measurement, after: event, seconds: seconds)
        let lines = switch kind {
        case .video: [back, decoder(measurement, after: event, seconds: seconds)]
        case .scene: [back, gpuBack(measurement, after: event), linkStopped(measurement, after: event)]
        }
        guard seconds.isEmpty else { return lines }
        return lines.map { line in
            var unmeasured = line
            unmeasured.measured = "not measured"
            unmeasured.outcome = .notMeasured
            return unmeasured
        }
    }

    /// The second from which each of the three stays at or under its highest paused sample, a process
    /// not running counting as 0. The decoder is the extension's own: other clients' would hide it leaving.
    private func processesBack(_ measurement: EnergyMeasurement, after event: Event, seconds: [Int]) -> Line {
        let processes = [Self.extensionProcess, Self.decoderProcess, Self.windowServer]
        let returns = processes.map { process -> Int? in
            let paused = measurement.loads(process, in: EnergyMeasurement.Phase.paused).values
            let ceiling = EnergyMeasurement.Load(cpu: paused.map(\.cpu).max() ?? 0, power: paused.map(\.power).max() ?? 0)
            let loads = measurement.loads(process, in: event.phase)
            return settled(seconds) { second in
                let load = loads[second] ?? .zero
                return load.cpu <= ceiling.cpu && load.power <= ceiling.power
            }
        }
        let slowest = returns.contains(nil) ? nil : returns.compactMap(\.self).max()
        return back(event.back, "All three at paused levels after \(event.words)", at: slowest, seconds: seconds)
    }

    /// powermetrics' GPU power from the second it stays at or under its highest paused second.
    /// Without watts in the phase, or while paused, it is not measured.
    private func gpuBack(_ measurement: EnergyMeasurement, after event: Event) -> Line {
        let name = "GPU at paused levels after \(event.words)"
        let gpu = measurement.gpuMilliwatts(in: event.phase)
        guard let ceiling = measurement.gpuMilliwatts(in: EnergyMeasurement.Phase.paused).values.max(), !gpu.isEmpty else {
            return Line(check: event.gpu, name: name, measured: "not measured", limit: "within \(returnSeconds) s", outcome: .notMeasured)
        }
        let seconds = gpu.keys.sorted()
        return back(event.gpu, name, at: settled(seconds) { (gpu[$0] ?? 0) <= ceiling }, seconds: seconds)
    }

    private func back(_ check: Check, _ name: String, at second: Int?, seconds: [Int]) -> Line {
        Line(
            check: check, name: name, measured: second.map { "\($0) s" } ?? "not back in \(seconds.last ?? 0) s",
            limit: "within \(returnSeconds) s", outcome: second.map { $0 <= returnSeconds } == true ? .pass : .fail
        )
    }

    /// The extension's first `stopped drawing at` line after the event, from `link.csv`: with the file
    /// given, a phase with no row is a link that never stopped.
    private func linkStopped(_ measurement: EnergyMeasurement, after event: Event) -> Line {
        let name = "The scene's link stopped after \(event.words)"
        let limit = "within \(returnSeconds) s"
        guard let links = measurement.links else {
            return Line(check: event.link, name: name, measured: "not measured", limit: limit, outcome: .notMeasured)
        }
        guard let stop = links.first(where: { $0.phase == event.phase }) else {
            return Line(check: event.link, name: name, measured: "no stop in the extension's log", limit: limit, outcome: .fail)
        }
        let outcome: Outcome = stop.seconds <= Double(returnSeconds) ? .pass : .fail
        return Line(check: event.link, name: name, measured: "at \(format(stop.seconds)) s", limit: limit, outcome: outcome)
    }

    /// The extension's own decoder: kept while covered, its session released while the display sleeps.
    private func decoder(_ measurement: EnergyMeasurement, after event: Event, seconds: [Int]) -> Line {
        let decoders = measurement.loads(Self.decoderProcess, in: event.phase)
        guard event.decoder == .decoderGoneWhenAsleep else {
            let kept = seconds.allSatisfy { decoders[$0] != nil }
            return Line(
                check: event.decoder, name: "The extension's VTDecoderXPCService kept while covered",
                measured: kept ? "kept" : "released", limit: "kept", outcome: kept ? .pass : .fail
            )
        }
        return released(decoders, seconds: seconds, measurement: measurement)
    }

    /// The `VTDecoderXPCService` process was found never to exit, so "gone" is no session and
    /// no buffers: a service that exits is judged by when, and one still running is recorded with its
    /// footprint against its footprint while playing, for a person to read.
    private func released(_ decoders: [Int: EnergyMeasurement.Load], seconds: [Int], measurement: EnergyMeasurement) -> Line {
        let name = "The extension's VTDecoderXPCService gone while the display sleeps"
        let limit = "no session and no buffers within \(returnSeconds) s"
        if let gone = settled(seconds, { decoders[$0] == nil }) {
            let outcome: Outcome = gone <= returnSeconds ? .pass : .fail
            return Line(check: .decoderGoneWhenAsleep, name: name, measured: "exited at \(gone) s", limit: limit, outcome: outcome)
        }
        let last = seconds.last.flatMap { decoders[$0] }?.memoryKilobytes ?? 0
        let playing = measurement.mean(Self.decoderProcess, in: EnergyMeasurement.Phase.playing)?.memoryKilobytes
        let measured = "running, \(megabytes(last)) at the end" + (playing.map { ", \(megabytes($0)) playing" } ?? "")
        return Line(check: .decoderGoneWhenAsleep, name: name, measured: measured, limit: limit, outcome: .recorded)
    }

    private func megabytes(_ kilobytes: Double) -> String {
        "\(format(kilobytes / 1_024)) MB"
    }

    /// The first second from which `holds` is true to the phase's end, or nil.
    private func settled(_ seconds: [Int], _ holds: (Int) -> Bool) -> Int? {
        var first: Int?
        for second in seconds {
            if holds(second) {
                first = first ?? second
            } else {
                first = nil
            }
        }
        return first
    }
}
