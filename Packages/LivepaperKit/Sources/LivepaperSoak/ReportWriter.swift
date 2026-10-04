import Foundation

/// The soak report's Markdown, section by section.
struct ReportWriter {
    private(set) var text = ""
    private let clock: DateFormatter
    private let day: DateFormatter

    /// Lines kept for an episode: from 5 s before it opened, or its trigger when that is within a minute.
    static let excerptLead: TimeInterval = 5
    static let triggerReach: TimeInterval = 60
    static let excerptLimit = 40
    static let unparsedLimit = 50
    /// How long after a replug its first check is looked for.
    static let checkReach: TimeInterval = 300

    init(timeZone: TimeZone) {
        clock = DateFormatter()
        clock.locale = Locale(identifier: "en_US_POSIX")
        clock.timeZone = timeZone
        clock.dateFormat = "yyyy-MM-dd HH:mm:ss"
        day = DateFormatter()
        day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = timeZone
        day.dateFormat = "yyyy-MM-dd"
    }

    fileprivate mutating func add(_ line: String) {
        text += line + "\n"
    }

    fileprivate func time(_ date: Date) -> String {
        clock.string(from: date)
    }

    fileprivate func date(_ date: Date) -> String {
        day.string(from: date)
    }

    fileprivate var zone: String {
        clock.timeZone.abbreviation() ?? clock.timeZone.identifier
    }
}

// MARK: The soak and its episodes

extension ReportWriter {
    mutating func header(verdict: SoakReport.Verdict, start: Date?, end: Date?) {
        add("# Soak\(start.map { ", " + date($0) } ?? "")")
        add("")
        switch verdict {
        case .noSoak(let reason):
            add("**No soak**: \(reason). Nothing here is judged.")
        case .pass:
            add("**Pass**: no unrecovered episode outside a drill, and memory within 10 %.")
        case .incomplete(let reasons):
            add("**Incomplete**: \(reasons.joined(separator: "; ")).")
        case .fail(let reasons):
            add("**Fail**: \(reasons.joined(separator: "; ")).")
        }
        add("")
        add("| | |")
        add("|---|---|")
        if let start, let end {
            add(
                "| Soak | \(time(start)) to \(time(end)) \(zone), "
                    + "\(duration(end.timeIntervalSince(start))), from the first `host: status live` |"
            )
        }
    }

    mutating func inputs(log: SoakLog, samples: Int, unreadSamples: Int, markers: Int, unreadMarkers: Int) {
        let events = log.entries.count
        let known = log.lines.count - events - log.unparsed.count
        add(
            "| Log | \(log.lines.count) lines read: \(events) events, \(known) known, \(log.unparsed.count) unparsed; "
                + "\(log.ignoredCount) of other subsystems ignored |"
        )
        add("| Samples | \(samples) rows\(unreadSamples > 0 ? ", \(unreadSamples) unread" : "") |")
        add("| Markers | \(markers) rows\(unreadMarkers > 0 ? ", \(unreadMarkers) unread" : "") |")
        add("")
    }

    mutating func triggers(_ episodes: Episodes) {
        add("## Triggers")
        add("")
        add("Each episode is charged to the last trigger at or before it opened. A drill's episodes are judged by its row in the PR.")
        add("")
        add("| Trigger | Events | Episodes |")
        add("|---|---|---|")
        for kind in TriggerKind.allCases {
            let events = episodes.triggers.filter { $0.kind == kind }.count
            add("| \(name(of: kind)) | \(events) | \(summary(episodes.all.filter { $0.trigger?.kind == kind })) |")
        }
        let before = episodes.all.filter { $0.trigger == nil }
        if !before.isEmpty { add("| before any trigger | | \(summary(before)) |") }
        add("")
    }

    mutating func episodes(_ episodes: Episodes, log: SoakLog) {
        add("## Episodes")
        add("")
        guard !episodes.all.isEmpty else {
            add("None.")
            add("")
            return
        }
        for (index, episode) in episodes.all.enumerated() {
            let outcome = episode.outcome == .recovered ? episode.outcome.words : "unrecovered: \(episode.outcome.words)"
            add("### \(index + 1). \(subject(episode.subject)), \(episode.level.rawValue), \(outcome)")
            add("")
            var facts: [String] = []
            if case .surface(let tag) = episode.subject {
                facts.append("Wallpaper \(tag.wallpaper ?? "none"), generation \(tag.generation.map(String.init) ?? "none").")
            }
            let closed = episode.closed.map { ", closed \(time($0)) (\(duration($0.timeIntervalSince(episode.opened))))" } ?? ""
            facts.append("Opened \(time(episode.opened))\(closed).")
            if let trigger = episode.trigger {
                let note = trigger.note.map { " (\($0))" } ?? ""
                facts.append(
                    "Charged to \(name(of: trigger.kind))\(note) at \(time(trigger.time)), "
                        + "\(duration(episode.opened.timeIntervalSince(trigger.time))) before."
                )
            } else {
                facts.append("No trigger before it.")
            }
            add(facts.joined(separator: " "))
            add("")
            add("```")
            excerpt(for: episode, log: log).forEach { add($0) }
            add("```")
            add("")
        }
    }

    /// Each display that came back or changed mode: how soon it showed its wallpaper, and the first check
    /// after it on it and on the others (the hot-plug loop's "within 2 s" and "`.healthy` at attempt 0 on both").
    mutating func replugs(_ episodes: Episodes, log: SoakLog) {
        let replugs = episodes.triggers.filter { $0.display != nil }
        guard !replugs.isEmpty else { return }
        add("## Replugs and mode changes")
        add("")
        add("| Time | Display | Shown | First verdict | Other displays |")
        add("|---|---|---|---|---|")
        let displays = Set(log.entries.compactMap { entry -> String? in
            if case .verdict(let tag, _, _) = entry.event, !tag.isPreview { tag.display } else { nil }
        })
        for trigger in replugs {
            guard let display = trigger.display else { continue }
            let others = displays.subtracting([display]).sorted().map { "\($0): \(firstVerdict(on: $0, after: trigger.time, log: log))" }
            let onScreen = shown(on: display, after: trigger.time, log: log)
            let verdict = firstVerdict(on: display, after: trigger.time, log: log)
            let elsewhere = others.isEmpty ? "none" : others.joined(separator: "; ")
            add("| \(time(trigger.time)) | \(display) | \(onScreen) | \(verdict) | \(elsewhere) |")
        }
        add("")
    }
}

// MARK: Playback, memory and the service

extension ReportWriter {
    mutating func gaps(_ gaps: WallpaperGaps) {
        add("## Presented gaps")
        add("")
        guard !gaps.wallpapers.isEmpty else {
            add("No metrics lines: the playback-metrics probe was off.")
            add("")
            return
        }
        add(
            "In frame durations, from the metrics lines: late frames, the late-frame question's, which the 200-loop row on an idle "
                + "machine settles as load or the engine's. The engine's own seam step (1.00 is gapless) and seam lead say whether "
                + "a late seam picture was queued on time."
        )
        add("")
        add("| Wallpaper | Loops | Largest gap | Where | Over 1.5 at seams | Over 1.5 mid-pass | Seam step | Seam lead |")
        add("|---|---|---|---|---|---|---|---|")
        for wallpaper in gaps.wallpapers {
            let largest = wallpaper.largest.map { String(format: "%.2f", $0) } ?? "none"
            let place = wallpaper.largest == nil ? "" : wallpaper.isLargestAtSeam ? "at a seam" : "mid-pass"
            let step = wallpaper.largestSeamStep.map { String(format: "%.2f", $0) } ?? "none"
            let lead = wallpaper.smallestSeamLead.map { String(format: "%.2f s", $0) } ?? "none"
            add(
                "| \(wallpaper.folder) | \(wallpaper.loops) | \(largest) | \(place) | "
                    + "\(wallpaper.overLimitAtSeams) | \(wallpaper.overLimitMidPass) | \(step) | \(lead) |"
            )
        }
        add("")
    }

    mutating func memory(_ trends: [MemoryTrend]) {
        add("## Memory")
        add("")
        add(
            "Mean RSS by quarter hour from the soak's start. The last quarter hour's mean may be at most 10 % over the second's; "
                + "the first is warm-up."
        )
        add("")
        add("| Minutes | " + trends.map(\.process).joined(separator: " | ") + " |")
        add("|---|" + trends.map { _ in "---|" }.joined())
        let windows = Set(trends.flatMap(\.windowMeans.keys)).sorted()
        for window in windows {
            let means = trends.map { $0.windowMeans[window].map { String(format: "%.1f MB", $0 / 1_024) } ?? "" }
            add("| \(MemoryTrend.minutes(of: window)) | " + means.joined(separator: " | ") + " |")
        }
        add("")
        for trend in trends {
            let verdict = switch trend.verdict {
            case .pass(let growth): "pass, the last quarter hour is \(change(growth)) the second"
            case .fail(let growth): "fail, the last quarter hour is \(change(growth)) the second"
            case .inconclusive(let reason): "inconclusive: \(reason)"
            }
            add("- \(trend.process), \(trend.sampleCount) samples: \(verdict).")
        }
        add("")
    }

    mutating func service(log: SoakLog, restarts: [Date], episodes: Episodes) {
        add("## The service")
        add("")
        var checks: [String] = []
        var launches = 0
        var spirals = 0
        for entry in log.entries {
            switch entry.event {
            case .selfCheck(let isUsable, let missing):
                checks.append(
                    missing.isEmpty ? "all present" : "\(isUsable ? "usable" : "failed"), missing: \(missing.joined(separator: ", "))"
                )
            case .extensionLaunched: launches += 1
            case .spiral: spirals += 1
            default: break
            }
        }
        add("- Bridge self-check: \(checks.isEmpty ? "not in the log" : Set(checks).sorted().map { "`\($0)`" }.joined(separator: ", ")).")
        add("- Extension launches: \(launches).")
        let closest = zip(restarts, restarts.dropFirst()).map { $1.timeIntervalSince($0) }.min()
        let apart = closest.map { ", the closest two \(Int($0.rounded())) s apart" } ?? ""
        add("- WallpaperAgent restarts by the app: \(restarts.count)\(apart).")
        add("- Spiral detections: \(spirals).")
        add("- Recover verdicts on a covered display: \(episodes.judgedWhileCovered.count).")
        add("")
    }

    mutating func unparsed(_ lines: [LogLine]) {
        guard !lines.isEmpty else { return }
        add("## Unparsed lines")
        add("")
        add("Lines of the categories the soak reads that it did not recognise: a wording that changed, or a line it has no row for.")
        add("")
        add("```")
        lines.prefix(Self.unparsedLimit).forEach { add($0.text) }
        if lines.count > Self.unparsedLimit { add("… and \(lines.count - Self.unparsedLimit) more") }
        add("```")
        add("")
    }
}

// MARK: Pieces

private extension ReportWriter {
    func excerpt(for episode: Episode, log: SoakLog) -> [String] {
        var from = episode.opened.addingTimeInterval(-Self.excerptLead)
        if let trigger = episode.trigger, episode.opened.timeIntervalSince(trigger.time) <= Self.triggerReach {
            from = min(from, trigger.time)
        }
        let to = (episode.closed ?? episode.opened.addingTimeInterval(Self.triggerReach)).addingTimeInterval(1)
        let lines = log.lines.filter { $0.time >= from && $0.time <= to }
        var excerpt = lines.prefix(Self.excerptLimit).map(\.text)
        if lines.count > Self.excerptLimit { excerpt.append("… and \(lines.count - Self.excerptLimit) more") }
        return excerpt
    }

    /// What the display's desktop surface showed first after `time`, and how soon.
    func shown(on display: String, after time: Date, log: SoakLog) -> String {
        for entry in log.entries where entry.line.time >= time && entry.line.time <= time.addingTimeInterval(Self.triggerReach) {
            guard case .shows(let tag, let content) = entry.event, tag.display == display, !tag.isPreview else { continue }
            let wallpaper = tag.wallpaper ?? "nothing"
            let what = switch content {
            case .playing: wallpaper
            case .still: "\(wallpaper) held still"
            case .nothing: "nothing"
            }
            return "\(what) in \(duration(entry.line.time.timeIntervalSince(time)))"
        }
        return "nothing within \(Int(Self.triggerReach)) s"
    }

    func firstVerdict(on display: String, after time: Date, log: SoakLog) -> String {
        for entry in log.entries where entry.line.time >= time && entry.line.time <= time.addingTimeInterval(Self.checkReach) {
            guard case .verdict(let tag, let verdict, let attempt) = entry.event, tag.display == display, !tag.isPreview else { continue }
            let words = switch verdict {
            case .healthy: "healthy"
            case .notComposited: "notComposited"
            case .recover(let level): level.rawValue
            }
            return "\(words), attempt \(attempt)"
        }
        return "no check within \(Int(Self.checkReach / 60)) min"
    }

    func summary(_ episodes: [Episode]) -> String {
        guard !episodes.isEmpty else { return "none" }
        return LadderLevel.allCases.compactMap { level -> String? in
            let own = episodes.filter { $0.level == level }
            guard !own.isEmpty else { return nil }
            let outcomes: [Episode.Outcome] = [
                .recovered, .unrecovered(.reachedRestart), .unrecovered(.neverClosed), .unrecovered(.openAtEnd),
            ]
            let parts = outcomes.compactMap { outcome -> String? in
                let count = own.filter { $0.outcome == outcome }.count
                return count > 0 ? "\(count) \(outcome.words)" : nil
            }
            return "\(level.rawValue): \(parts.joined(separator: ", "))"
        }.joined(separator: "; ")
    }

    func name(of kind: TriggerKind) -> String {
        switch kind {
        case .wake: "wake"
        case .lid: "lid, asleep"
        case .lidOnExternal: "lid, awake on the external"
        case .displayWake: "display wake"
        case .unlock: "unlock"
        case .replug: "replug or mode change"
        case .rotation: "rotation"
        case .restart: "restart"
        case .userSwitch: "fast user switch"
        case .drill: "drill"
        }
    }

    func subject(_ subject: Episode.Subject) -> String {
        switch subject {
        case .surface(let tag): "\(tag.isPreview ? "Preview surface" : "Surface") \(tag.surface) on display \(tag.display)"
        case .host: "The host"
        }
    }

    /// `9 % over`, or `47 % under`.
    func change(_ growth: Double) -> String {
        growth < 0 ? "\(percent(-growth)) % under" : "\(percent(growth)) % over"
    }

    func duration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return String(format: "%.1f s", seconds) }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes) min \(Int(seconds) % 60) s" }
        return "\(minutes / 60) h \(minutes % 60) min"
    }
}

extension Episode.Outcome {
    /// `recovered`, or how it was not.
    var words: String {
        switch self {
        case .recovered: "recovered"
        case .unrecovered(.reachedRestart): "reached the restart"
        case .unrecovered(.neverClosed): "never closed"
        case .unrecovered(.openAtEnd): "open at the end"
        }
    }
}
