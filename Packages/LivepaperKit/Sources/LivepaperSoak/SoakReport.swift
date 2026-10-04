import Foundation

/// A soak's log, samples and markers read into its report:
/// per trigger, the events and the episodes by
/// level and outcome; the largest presented gap per wallpaper; RSS by hour; and
/// every episode's excerpt. The next soak compares against it.
public struct SoakReport: Sendable {
    public enum Verdict: Equatable, Sendable {
        /// Nothing to judge: an empty log is no soak, never a pass.
        case noSoak(String)
        case pass
        /// Nothing failed, but a rule could not be judged.
        case incomplete([String])
        case fail([String])
    }

    /// "No agent restart twice in 600 s" (`AgentRestart`).
    public static let agentRestartGap: TimeInterval = 600
    /// The app and the extension, whose memory the soak holds to its rule.
    public static let processes = ["Livepaper", "WallpaperExtension"]

    /// The first `host: status live`: the soak's clock starts there.
    public let start: Date?
    public let end: Date?
    public let episodes: Episodes
    public let gaps: WallpaperGaps
    public let memory: [MemoryTrend]
    public let verdict: Verdict
    public let markdown: String

    public init(
        log: SoakLog, samples: [ResourceSample], markers: [SoakMarker],
        unreadSampleRows: Int = 0, unreadMarkerRows: Int = 0, timeZone: TimeZone
    ) {
        let start = log.entries.first { $0.event == .hostStatus(.live) }?.line.time
        let end = markers.last { $0.kind == .end }?.time ?? [log.lines.last?.time, samples.map(\.time).max()].compactMap(\.self).max()
        let episodes = Episodes(log: log, markers: markers)
        let gaps = WallpaperGaps(log.entries.compactMap { if case .metrics(let line) = $0.event { line } else { nil } })
        let memory = Self.processes.map { MemoryTrend(process: $0, samples: samples, start: start ?? .distantPast) }
        let restarts = log.entries.filter { if case .agentRestarted = $0.event { true } else { false } }.map(\.line.time)
        self.start = start
        self.end = end
        self.episodes = episodes
        self.gaps = gaps
        self.memory = memory
        verdict = Self.verdict(start: start, episodes: episodes, gaps: gaps, memory: memory, restarts: restarts)

        var writer = ReportWriter(timeZone: timeZone)
        writer.header(verdict: verdict, start: start, end: end)
        writer.inputs(
            log: log, samples: samples.count, unreadSamples: unreadSampleRows, markers: markers.count, unreadMarkers: unreadMarkerRows
        )
        if start != nil {
            writer.triggers(episodes)
            writer.episodes(episodes, log: log)
            writer.replugs(episodes, log: log)
            writer.gaps(gaps)
            writer.memory(memory)
            writer.service(log: log, restarts: restarts, episodes: episodes)
        }
        writer.unparsed(log.unparsed)
        markdown = writer.text
    }

    private static func verdict(
        start: Date?, episodes: Episodes, gaps: WallpaperGaps, memory: [MemoryTrend], restarts: [Date]
    ) -> Verdict {
        guard start != nil else { return .noSoak("the log has no `host: status live`") }
        var failures: [String] = []
        // A drill's episodes are judged by its own row in "Recovery drills".
        let unrecovered = episodes.all.filter { $0.outcome != .recovered && $0.trigger?.kind != .drill }.count
        if unrecovered > 0 { failures.append(counted(unrecovered, "unrecovered episode")) }
        for trend in memory {
            if case .fail(let growth) = trend.verdict { failures.append("\(trend.process)'s memory grew \(percent(growth)) %") }
        }
        for (earlier, later) in zip(restarts, restarts.dropFirst()) where later.timeIntervalSince(earlier) < agentRestartGap {
            failures.append("2 agent restarts \(Int(later.timeIntervalSince(earlier).rounded())) s apart, under \(Int(agentRestartGap)) s")
        }
        if !episodes.judgedWhileCovered.isEmpty {
            failures.append(counted(episodes.judgedWhileCovered.count, "recover verdict") + " on a covered display")
        }
        if !failures.isEmpty { return .fail(failures) }
        var unjudged = gaps.wallpapers.isEmpty ? ["no metrics lines: the playback-metrics probe was off"] : []
        unjudged += memory.compactMap { trend -> String? in
            if case .inconclusive(let reason) = trend.verdict { "\(trend.process)'s memory: \(reason)" } else { nil }
        }
        return unjudged.isEmpty ? .pass : .incomplete(unjudged)
    }
}

func counted(_ count: Int, _ singular: String, _ plural: String? = nil) -> String {
    "\(count) \(count == 1 ? singular : plural ?? singular + "s")"
}

func percent(_ fraction: Double) -> Int {
    Int((fraction * 100).rounded())
}
