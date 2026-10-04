import Foundation

/// One process at one of `soak.sh`'s five-minute samples: a row of `samples.csv`,
/// `time,process,pid,cpu,rss_kb`.
public struct ResourceSample: Equatable, Sendable {
    public var time: Date
    public var process: String
    public var pid: Int
    /// Percent of one core, at that moment.
    public var cpu: Double
    public var rssKilobytes: Int

    public init(time: Date, process: String, pid: Int, cpu: Double, rssKilobytes: Int) {
        self.time = time
        self.process = process
        self.pid = pid
        self.cpu = cpu
        self.rssKilobytes = rssKilobytes
    }

    /// Every row after the header; a row that does not read is counted, not guessed at.
    public static func read(csv: String) -> (samples: [ResourceSample], unreadRows: Int) {
        CSV.read(csv, header: "time,process,pid,cpu,rss_kb") { row in
            guard row.count == 5, let time = Timestamp.date(row[0]), !row[1].isEmpty, let pid = Int(row[2]),
                  let cpu = Double(row[3]), let rss = Int(row[4]) else { return nil }
            return ResourceSample(time: time, process: String(row[1]), pid: pid, cpu: cpu, rssKilobytes: rss)
        }
    }
}

/// One process's resident memory over the two-hour soak, by quarter hour from
/// its start, and the rule it is held to: the last quarter hour's mean at most
/// 10 % over the second's; the first is warm-up; under 100 samples, inconclusive.
public struct MemoryTrend: Equatable, Sendable {
    public enum Verdict: Equatable, Sendable {
        /// `growth` is the last window's mean over the second's, less one.
        case pass(growth: Double)
        case fail(growth: Double)
        case inconclusive(String)
    }

    /// A quarter hour, and the soak's eight of them.
    public static let window: TimeInterval = 15 * 60
    public static let minimumSamples = 100
    public static let allowedGrowth = 0.10
    public static let firstWindow = 2
    public static let lastWindow = 8

    public var process: String
    /// Mean RSS in kilobytes, by window: window 1 is the soak's first quarter hour.
    public var windowMeans: [Int: Double]
    public var sampleCount: Int
    public var verdict: Verdict

    public init(process: String, samples: [ResourceSample], start: Date) {
        let own = samples.filter { $0.process == process && $0.time >= start }
        var byWindow: [Int: [Int]] = [:]
        for sample in own {
            byWindow[Int(sample.time.timeIntervalSince(start) / Self.window) + 1, default: []].append(sample.rssKilobytes)
        }
        self.process = process
        windowMeans = byWindow.mapValues { Double($0.reduce(0, +)) / Double($0.count) }
        sampleCount = own.count
        if own.count < Self.minimumSamples {
            verdict = .inconclusive("\(own.count) samples, under \(Self.minimumSamples)")
        } else if let first = windowMeans[Self.firstWindow], let last = windowMeans[Self.lastWindow] {
            let growth = last / first - 1
            verdict = growth <= Self.allowedGrowth ? .pass(growth: growth) : .fail(growth: growth)
        } else {
            let missing = windowMeans[Self.firstWindow] == nil ? Self.firstWindow : Self.lastWindow
            verdict = .inconclusive("no samples in minutes \(Self.minutes(of: missing))")
        }
    }

    /// `15–30` for window 2.
    public static func minutes(of window: Int) -> String {
        let length = Int(Self.window / 60)
        return "\((window - 1) * length)–\(window * length)"
    }
}
