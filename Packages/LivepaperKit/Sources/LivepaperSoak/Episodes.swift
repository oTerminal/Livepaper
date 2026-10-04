import Foundation

/// A stall, from where it opened to where it closed.
public struct Episode: Equatable, Sendable {
    public enum Subject: Equatable, Sendable {
        /// A surface, as the line that opened the episode named it.
        case surface(SurfaceTag)
        case host
    }

    public enum Outcome: Equatable, Sendable {
        case recovered
        case unrecovered(Unrecovered)
    }

    /// The three ways an episode is unrecovered.
    public enum Unrecovered: Equatable, Sendable {
        /// It reached `.restartAgent`, which redraws every desktop, whether or not it closed after.
        case reachedRestart
        /// Its surface went away, or the extension started again, before a `.healthy`.
        case neverClosed
        case openAtEnd
    }

    public var subject: Subject
    public var opened: Date
    public var closed: Date?
    /// The highest rung it reached.
    public var level: LadderLevel
    public var outcome: Outcome
    /// The last trigger at or before its opening; nil when none came before it.
    public var trigger: Trigger?

    public init(subject: Subject, opened: Date, closed: Date?, level: LadderLevel, outcome: Outcome, trigger: Trigger?) {
        self.subject = subject
        self.opened = opened
        self.closed = closed
        self.level = level
        self.outcome = outcome
        self.trigger = trigger
    }
}

/// What an episode is charged to.
public struct Trigger: Equatable, Sendable {
    public var kind: TriggerKind
    public var time: Date
    /// The display a replug, or a lid cycle the Mac stayed awake through, brought back.
    public var display: String?
    /// A marker's note: which drill.
    public var note: String?

    public init(kind: TriggerKind, time: Date, display: String? = nil, note: String? = nil) {
        self.kind = kind
        self.time = time
        self.display = display
        self.note = note
    }
}

/// The report's triggers, and the three it adds so
/// no episode is charged to something else: a restart, a fast user switch and a drill.
public enum TriggerKind: String, CaseIterable, Sendable {
    /// The Mac woke, from `soak.sh night` or anything but a marked lid.
    case wake
    /// The Mac woke after a person marked a lid cycle (`soak.sh mark lid`).
    case lid
    /// A marked lid cycle that the Mac stayed awake through on the external,
    /// the built-in display leaving and coming back.
    case lidOnExternal
    case displayWake
    case unlock
    /// A display came back as a new surface, or changed mode.
    case replug
    /// A rotation tick moved a display on. A wake's rotation stays the wake's.
    case rotation
    /// The extension started again, or a new WallpaperAgent connected.
    case restart
    /// A marked fast user switch (`soak.sh mark fus`).
    case userSwitch
    /// A marked recovery drill (`soak.sh mark drill <which>`). Its episodes are the
    /// drill's own, judged by its row in "Recovery drills", not by the soak's.
    case drill

    /// The Mac's wake and its displays': one wake may log both.
    var isWake: Bool { [.wake, .lid, .lidOnExternal, .displayWake].contains(self) }
}

/// A soak's episodes and triggers, reduced from its log in time order.
public struct Episodes: Sendable {
    public private(set) var all: [Episode] = []
    public private(set) var triggers: [Trigger] = []
    /// Recover verdicts on a surface whose display was covered: never a stall, and
    /// a watchdog that judged one is a finding of its own.
    public private(set) var judgedWhileCovered: [SoakLog.Entry] = []

    public init(log: SoakLog, markers: [SoakMarker]) {
        var reducer = Reducer()
        // A marker is written before what it marks, so at one instant it comes first.
        var markers = markers.sorted { $0.time < $1.time }[...]
        for entry in log.entries {
            while let marker = markers.first, marker.time <= entry.line.time {
                reducer.read(marker)
                markers = markers.dropFirst()
            }
            reducer.read(entry)
        }
        markers.forEach { reducer.read($0) }
        reducer.end()
        all = reducer.finished.sorted { ($0.episode.opened, $0.order) < ($1.episode.opened, $1.order) }.map(\.episode)
        triggers = reducer.triggers
        judgedWhileCovered = reducer.judgedWhileCovered
    }
}

/// The state the log is read through, one entry at a time.
private struct Reducer {
    /// An episode, and the place of the line that opened it, which orders episodes opened in the same instant.
    struct Tracked {
        var order: Int
        var episode: Episode
    }

    var finished: [Tracked] = []
    var triggers: [Trigger] = []
    var judgedWhileCovered: [SoakLog.Entry] = []

    /// Open surface episodes, by surface ID, and the host's.
    private var open: [String: Tracked] = [:]
    private var host: Tracked?
    private var hostPhase: HostPhase?
    private var decisions: [String: DisplayDecision] = [:]
    /// Surfaces on the lock screen, where covering does not count.
    private var lockedSurfaces: Set<String> = []
    private var opened = 0

    /// A person marked a lid cycle that no wake or replug has answered yet.
    private var isLidPending = false
    /// Displays whose desktop surface went away in this extension process.
    private var displaysGone: Set<String> = []
    private var lastReplug: [String: Date] = [:]
    /// Until when surfaces acquired again belong to a restart rather than a replug.
    private var restartWindowEnd: Date?
    private var agentPID: Int?
    private var hasSeenExtension = false

    /// Lines within this of a restart, or of a replug of the same display, belong to it.
    static let settling: TimeInterval = 10

    mutating func read(_ marker: SoakMarker) {
        switch marker.kind {
        case .lid: isLidPending = true
        case .sleep, .displaySleep: isLidPending = false
        case .fastUserSwitch: triggers.append(Trigger(kind: .userSwitch, time: marker.time))
        case .drill: triggers.append(Trigger(kind: .drill, time: marker.time, note: marker.note.isEmpty ? nil : marker.note))
        default: break
        }
    }

    mutating func read(_ entry: SoakLog.Entry) {
        let time = entry.line.time
        readTrigger(entry.event, at: time)
        readDisplays(entry.event, at: time)
        if entry.line.subsystem == Reading.extensionSubsystem { hasSeenExtension = true }
        if case .hostStatus(let phase) = entry.event {
            readHost(phase, at: time)
        } else {
            readSurface(entry, at: time)
        }
    }

    // MARK: Episodes

    private mutating func readSurface(_ entry: SoakLog.Entry, at time: Date) {
        switch entry.event {
        case .verdict(let tag, let verdict, _):
            readVerdict(verdict, on: tag, entry: entry)
        case .restartRequested(let tag):
            open[tag.surface]?.episode.level.raise(to: .restartAgent)
        case .invalidated(let tag), .tornDown(let tag):
            if let episode = open.removeValue(forKey: tag.surface) { finish(episode, unrecovered: .neverClosed) }
        case .extensionLaunched:
            for episode in open.values { finish(episode, unrecovered: .neverClosed) }
            open = [:]
        default:
            break
        }
    }

    /// A recover verdict opens a surface's episode or raises its level; `.healthy` closes it.
    private mutating func readVerdict(_ verdict: CheckVerdict, on tag: SurfaceTag, entry: SoakLog.Entry) {
        let time = entry.line.time
        switch verdict {
        case .recover where decisions[tag.display]?.isCovered == true && !lockedSurfaces.contains(tag.surface):
            judgedWhileCovered.append(entry)
        case .recover(let level):
            if open[tag.surface] == nil { open[tag.surface] = opening(.surface(tag), at: time, level: level) }
            open[tag.surface]?.episode.level.raise(to: level)
        case .healthy:
            if let episode = open.removeValue(forKey: tag.surface) { finish(episode, closed: time) }
        case .notComposited:
            break
        }
    }

    /// The host's episode opens when its status leaves `.live` for `.recovering(_)`, and closes at the next `.live`.
    private mutating func readHost(_ phase: HostPhase, at time: Date) {
        if case .recovering(let level) = phase {
            if host != nil {
                host?.episode.level.raise(to: level)
            } else if hostPhase == .live {
                host = opening(.host, at: time, level: level)
            }
        } else if phase == .live, let episode = host {
            finish(episode, closed: time)
            host = nil
        }
        hostPhase = phase
    }

    // MARK: Triggers

    private mutating func readTrigger(_ event: SoakEvent, at time: Date) {
        switch event {
        case .woke(let source):
            woke(source, at: time)
        case .unlocked:
            trigger(.unlock, at: time)
        case .rotated(.tick, let displays) where !displays.isEmpty:
            trigger(.rotation, at: time)
        case .extensionLaunched:
            if hasSeenExtension { restart(at: time) }
        case .agentConnected(let pid):
            if let agentPID, agentPID != pid { restart(at: time) }
            agentPID = pid
        default:
            break
        }
    }

    /// Each display's decision. A desktop surface gone and a new one for its display is a replug; so is a display's new mode.
    private mutating func readDisplays(_ event: SoakEvent, at time: Date) {
        switch event {
        case .decision(let display, let decision):
            decisions[display] = decision
        case .mode(let tag, let isLocked):
            if isLocked { lockedSurfaces.insert(tag.surface) } else { lockedSurfaces.remove(tag.surface) }
        case .invalidated(let tag), .tornDown(let tag):
            if !tag.isPreview { displaysGone.insert(tag.display) }
        case .acquired(let tag, reused: false) where !tag.isPreview && displaysGone.contains(tag.display):
            displaysGone.remove(tag.display)
            replug(tag.display, at: time)
        case .displayReconfigured(let display):
            replug(display, at: time)
        case .extensionLaunched:
            displaysGone = []
        default:
            break
        }
    }

    private mutating func replug(_ display: String, at time: Date) {
        if let restartWindowEnd, time <= restartWindowEnd { return }
        if let last = lastReplug[display], time.timeIntervalSince(last) <= Self.settling { return }
        lastReplug[display] = time
        trigger(isLidPending ? .lidOnExternal : .replug, at: time, display: display)
    }

    /// The Mac's wake and its displays' within `settling` of each other are one wake,
    /// the Mac's deciding its kind: the displays woke because the Mac did.
    private mutating func woke(_ source: WakeSource, at time: Date) {
        if let last = triggers.last, last.kind.isWake, last.display == nil, time.timeIntervalSince(last.time) <= Self.settling {
            if source == .system, last.kind == .displayWake || last.kind == .lidOnExternal {
                triggers[triggers.count - 1].kind = last.kind == .lidOnExternal ? .lid : .wake
            }
            return
        }
        switch source {
        case .system: trigger(isLidPending ? .lid : .wake, at: time)
        case .displays: trigger(isLidPending ? .lidOnExternal : .displayWake, at: time)
        }
    }

    private mutating func restart(at time: Date) {
        restartWindowEnd = time.addingTimeInterval(Self.settling)
        trigger(.restart, at: time)
    }

    private mutating func trigger(_ kind: TriggerKind, at time: Date, display: String? = nil) {
        if [.lid, .lidOnExternal].contains(kind) { isLidPending = false }
        triggers.append(Trigger(kind: kind, time: time, display: display))
    }

    /// The soak ended: what is still open stays open.
    mutating func end() {
        for episode in open.values { finish(episode, unrecovered: .openAtEnd) }
        if let host { finish(host, unrecovered: .openAtEnd) }
        open = [:]
        host = nil
    }

    private mutating func opening(_ subject: Episode.Subject, at time: Date, level: LadderLevel) -> Tracked {
        opened += 1
        let episode = Episode(subject: subject, opened: time, closed: nil, level: level, outcome: .recovered, trigger: triggers.last)
        return Tracked(order: opened, episode: episode)
    }

    /// Closed by a `.healthy` or `.live`: recovered, unless it reached `.restartAgent` on the way.
    private mutating func finish(_ tracked: Tracked, closed: Date) {
        var tracked = tracked
        tracked.episode.closed = closed
        tracked.episode.outcome = tracked.episode.level == .restartAgent ? .unrecovered(.reachedRestart) : .recovered
        finished.append(tracked)
    }

    private mutating func finish(_ tracked: Tracked, unrecovered: Episode.Unrecovered) {
        var tracked = tracked
        tracked.episode.outcome = .unrecovered(tracked.episode.level == .restartAgent ? .reachedRestart : unrecovered)
        finished.append(tracked)
    }
}

private extension LadderLevel {
    mutating func raise(to level: LadderLevel) {
        self = max(self, level)
    }
}
