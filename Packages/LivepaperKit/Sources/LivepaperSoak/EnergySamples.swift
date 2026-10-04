import Foundation

/// One process in one `top` sample of `energy.sh`: a row of `energy.csv`,
/// `phase,second,process,pid,cpu,power,mem_kb`. `power` is top's unitless
/// energy-impact score, `mem_kb` its memory footprint.
public struct EnergySample: Equatable, Sendable {
    public var phase: String
    /// Seconds since the phase began: for `covered` and `displayAsleep`, since the event.
    public var second: Int
    /// `VTDecoderXPCService` is the extension's own decoder service, `VTDecoderXPCService.others` any other client's.
    public var process: String
    public var pid: Int
    public var cpu: Double
    public var power: Double
    public var memoryKilobytes: Int

    public init(phase: String, second: Int, process: String, pid: Int, cpu: Double, power: Double, memoryKilobytes: Int = 0) {
        self.phase = phase
        self.second = second
        self.process = process
        self.pid = pid
        self.cpu = cpu
        self.power = power
        self.memoryKilobytes = memoryKilobytes
    }

    public static func read(csv: String) -> (samples: [EnergySample], unreadRows: Int) {
        CSV.read(csv, header: "phase,second,process,pid,cpu,power,mem_kb") { row in
            guard row.count == 7, !row[0].isEmpty, let second = Int(row[1]), !row[2].isEmpty, let pid = Int(row[3]),
                  let cpu = Double(row[4]), let power = Double(row[5]), let memory = Int(row[6]) else { return nil }
            return EnergySample(
                phase: String(row[0]), second: second, process: String(row[2]), pid: pid, cpu: cpu, power: power, memoryKilobytes: memory
            )
        }
    }
}

/// One `powermetrics` sample, taken with `sudo`: a row of `watts.csv`, `phase,second,combined_mw,gpu_mw`.
public struct WattSample: Equatable, Sendable {
    public var phase: String
    public var second: Int
    public var combinedMilliwatts: Double
    public var gpuMilliwatts: Double

    public init(phase: String, second: Int, combinedMilliwatts: Double, gpuMilliwatts: Double) {
        self.phase = phase
        self.second = second
        self.combinedMilliwatts = combinedMilliwatts
        self.gpuMilliwatts = gpuMilliwatts
    }

    public static func read(csv: String) -> (samples: [WattSample], unreadRows: Int) {
        CSV.read(csv, header: "phase,second,combined_mw,gpu_mw") { row in
            guard row.count == 4, !row[0].isEmpty, let second = Int(row[1]), let combined = Double(row[2]),
                  let gpu = Double(row[3]) else { return nil }
            return WattSample(phase: String(row[0]), second: second, combinedMilliwatts: combined, gpuMilliwatts: gpu)
        }
    }
}

/// When a scene's display link stopped: a row of `link.csv`, `phase,seconds`, which `energy.sh` writes
/// for a scene after covering and after display sleep, from the extension's first `stopped drawing at`
/// line (`EngineLog.sceneStopped`) since the event. A phase whose log had no such line has no row.
public struct LinkStop: Equatable, Sendable {
    public var phase: String
    /// From the event to the line.
    public var seconds: Double

    public init(phase: String, seconds: Double) {
        self.phase = phase
        self.seconds = seconds
    }

    public static func read(csv: String) -> (stops: [LinkStop], unreadRows: Int) {
        CSV.read(csv, header: "phase,seconds") { row in
            guard row.count == 2, !row[0].isEmpty, let seconds = Double(row[1]) else { return nil }
            return LinkStop(phase: String(row[0]), seconds: seconds)
        }
    }
}

/// An `energy.sh` run: its samples by phase, each process's instances summed per sample.
public struct EnergyMeasurement: Equatable, Sendable {
    public enum Phase {
        public static let paused = "paused"
        public static let playing = "playing"
        public static let covered = "covered"
        public static let displayAsleep = "displayAsleep"
        public static let idleApp = "idleApp"
        public static let idleExtension = "idleExtension"
    }

    /// What a process cost at one second, or on average over a phase.
    public struct Load: Equatable, Sendable {
        public var cpu: Double
        public var power: Double
        public var memoryKilobytes: Double

        public init(cpu: Double, power: Double, memoryKilobytes: Double = 0) {
            self.cpu = cpu
            self.power = power
            self.memoryKilobytes = memoryKilobytes
        }

        /// A process not running.
        static let zero = Load(cpu: 0, power: 0)

        static func + (lhs: Load, rhs: Load) -> Load {
            Load(cpu: lhs.cpu + rhs.cpu, power: lhs.power + rhs.power, memoryKilobytes: lhs.memoryKilobytes + rhs.memoryKilobytes)
        }
    }

    public var samples: [EnergySample]
    /// Nil when `powermetrics` did not run: it "must be invoked as the superuser".
    public var watts: [WattSample]?
    /// A scene's `link.csv`; nil when none was given.
    public var links: [LinkStop]?

    public init(samples: [EnergySample], watts: [WattSample]? = nil, links: [LinkStop]? = nil) {
        self.samples = samples
        self.watts = watts
        self.links = links
    }

    public var phases: [String] {
        var seen: [String] = []
        for sample in samples where !seen.contains(sample.phase) { seen.append(sample.phase) }
        return seen
    }

    /// The seconds a phase was sampled at, whichever processes were running.
    public func seconds(in phase: String) -> [Int] {
        Set(samples.filter { $0.phase == phase }.map(\.second)).sorted()
    }

    /// The process at each second of the phase, every instance summed; a second it was not running at has none.
    /// top's clock is whole seconds, so two samples can share one: an instance's are averaged, then the instances summed.
    public func loads(_ process: String, in phase: String) -> [Int: Load] {
        var instances: [Int: [Int: [EnergySample]]] = [:]
        for sample in samples where sample.phase == phase && sample.process == process {
            instances[sample.second, default: [:]][sample.pid, default: []].append(sample)
        }
        return instances.mapValues { byPID in
            byPID.values.reduce(Load.zero) { sum, own in
                let count = Double(own.count)
                return sum + Load(
                    cpu: own.map(\.cpu).reduce(0, +) / count,
                    power: own.map(\.power).reduce(0, +) / count,
                    memoryKilobytes: Double(own.map(\.memoryKilobytes).reduce(0, +)) / count
                )
            }
        }
    }

    /// The mean over every second of the phase, a second the process was not running at counting as 0.
    public func mean(_ process: String, in phase: String) -> Load? {
        mean([process], in: phase)
    }

    /// The processes summed at each second of the phase, then the mean over every second, as `mean(_:in:)`.
    public func mean(_ processes: [String], in phase: String) -> Load? {
        let phaseSeconds = seconds(in: phase)
        guard !phaseSeconds.isEmpty else { return nil }
        let perProcess = processes.map { loads($0, in: phase) }
        let total = phaseSeconds.reduce(Load.zero) { sum, second in
            perProcess.reduce(sum) { $0 + ($1[second] ?? .zero) }
        }
        let count = Double(phaseSeconds.count)
        return Load(cpu: total.cpu / count, power: total.power / count, memoryKilobytes: total.memoryKilobytes / count)
    }

    /// powermetrics' GPU power at each second of the phase, in milliwatts, two samples in one second averaged;
    /// empty when it did not run.
    public func gpuMilliwatts(in phase: String) -> [Int: Double] {
        let own = (watts ?? []).filter { $0.phase == phase }
        return Dictionary(grouping: own, by: \.second).mapValues { $0.map(\.gpuMilliwatts).reduce(0, +) / Double($0.count) }
    }
}
