import Foundation

/// What one log line is to the soak. Lines of the categories it reads are an
/// event, a line it knows and does not count, or unparsed: counted and kept,
/// never dropped, so a line whose wording changed shows up in the report
/// instead of counting zero. Every other subsystem and category is ignored.
public enum Reading: Equatable, Sendable {
    case event(SoakEvent)
    case known
    case unparsed
    case ignored

    /// The extension's subsystem (`WallpaperExtensionIdentity.logSubsystem`) and the app's (`LivepaperSystem.logSubsystem`).
    public static let extensionSubsystem = "app.livepaper.extension"
    public static let appSubsystem = "app.livepaper.Livepaper"

    public init(_ line: LogLine) {
        let message = Substring(line.message)
        switch (line.subsystem, line.category) {
        case (Self.extensionSubsystem, "supervisor"): self = Self.supervisor(message)
        case (Self.extensionSubsystem, "extension"): self = Self.extensionLine(message)
        case (Self.extensionSubsystem, "bridge"): self = Self.bridge(message)
        case (Self.extensionSubsystem, "surface"): self = Self.surface(message)
        case (Self.appSubsystem, "host"): self = Self.host(message)
        case (Self.appSubsystem, "rotation"): self = Self.rotation(message)
        case (Self.appSubsystem, "sensing"): self = message.hasPrefix("sensing: covered [") ? .known : .unparsed
        default: self = .ignored
        }
    }

    // MARK: The extension and its bridge

    private static func extensionLine(_ message: Substring) -> Reading {
        let fields = Fields(message)
        if message.hasPrefix("extension: launched ") { return event(fields.int("pid").map { .extensionLaunched(pid: $0) }) }
        if message.hasPrefix("extension: woke ") {
            return event(fields["source"].flatMap(WakeSource.init(rawValue:)).map { .woke($0) })
        }
        if message == "extension: unlocked" { return .event(.unlocked) }
        if message.hasPrefix("extension: display reconfigured ") {
            return event(fields["display"].map { .displayReconfigured(display: $0) })
        }
        let phrases = [
            "no home folder ", "the settings tile is missing", "cannot observe ", "pointer read ", "context made ", "no context ",
            "no display ", "display unknown ", "acquire not done ", "context invalidated ", "surface resized ",
            "snapshot of unknown ", "snapshot not done ", "cannot watch display reconfiguration", "recover received ",
            "recover ignored ", "check received", "playback metrics probe ",
        ]
        return known(message, after: "extension: ", startsWithOneOf: phrases)
    }

    private static func bridge(_ message: Substring) -> Reading {
        if message == "bridge self-check: all present" { return .event(.selfCheck(isUsable: true, missing: [])) }
        for (phrase, isUsable) in [("bridge self-check: usable, missing: ", true), ("bridge self-check: failed, missing: ", false)]
        where message.hasPrefix(phrase) {
            let missing = message.dropFirst(phrase.count).split(separator: ", ").map(String.init)
            return .event(.selfCheck(isUsable: isUsable, missing: missing))
        }
        if message.hasPrefix("bridge: connection from pid "), message.hasSuffix(" accepted") {
            let pid = message.dropFirst("bridge: connection from pid ".count).dropLast(" accepted".count)
            return event(Int(pid).map { .agentConnected(pid: $0) })
        }
        if message.hasPrefix("bridge: spiral detected, ") {
            let count = message.dropFirst("bridge: spiral detected, ".count).prefix(while: \.isNumber)
            return event(Int(count).map { .spiral(emptyConnections: $0) })
        }
        let phrases = [
            "connection from pid ", "acquire surface ", "update surface ", "invalidate surface ", "snapshot surface ",
            "could not build ", "a second reply ", "notification ", "settings view models ", "the payload classes ",
        ]
        return known(message, after: "bridge: ", startsWithOneOf: phrases)
    }

    // MARK: The engine

    private static func surface(_ message: Substring) -> Reading {
        if message.hasPrefix("playback metrics for ") { return event(MetricsLine(logged: message).map { .metrics($0) }) }
        return ["engine: ", "layers: ", "scene: "].contains(where: message.hasPrefix) ? .known : .unparsed
    }

    // MARK: The app

    private static func host(_ message: Substring) -> Reading {
        if message.hasPrefix("host: status ") {
            return event(HostPhase(logged: message.dropFirst("host: status ".count)).map { .hostStatus($0) })
        }
        if message.hasPrefix("host: restarting WallpaperAgent ("), message.hasSuffix(")") {
            let reason = message.dropFirst("host: restarting WallpaperAgent (".count).dropLast()
            return .event(.agentRestarting(reason: String(reason)))
        }
        if message.hasPrefix("host: WallpaperAgent restarted, pid ") {
            let pids = message.dropFirst("host: WallpaperAgent restarted, pid ".count).split(separator: " -> ")
            guard pids.count == 2, let previous = Int(pids[0]), let current = Int(pids[1]) else { return .unparsed }
            return .event(.agentRestarted(previous: previous, current: current))
        }
        let phrases = [
            "activated, ", "no heartbeat, asking ", "no heartbeat since activation, ", "asking the extension to ",
            "WallpaperAgent pid ", "WallpaperAgent is not running", "could not signal WallpaperAgent ",
            "not restarting WallpaperAgent ", "render state ", "no render state to stop", "playback metrics ", "check requested",
        ]
        return known(message, after: "host: ", startsWithOneOf: phrases)
    }

    private static func rotation(_ message: Substring) -> Reading {
        for cause in [RotationCause.tick, .wake] where message.hasPrefix("rotation: \(cause.rawValue) rotated ") {
            let list = message.dropFirst("rotation: \(cause.rawValue) rotated ".count)
            let displays = list == "nothing" ? [] : list.split(separator: ", ").map(String.init)
            return .event(.rotated(cause, displays: displays))
        }
        let phrases = ["session started ", "next tick at ", "no tick due", "a tick moved nothing"]
        if known(message, after: "rotation: ", startsWithOneOf: phrases) == .known { return .known }
        return message.contains(" counts from ") || message.contains(" count from ") ? .known : .unparsed
    }

    // MARK: The supervisor

    /// Each phrase a supervisor line starts with, and what its fields make of it;
    /// nil is a line the soak knows and does not count. `invalidate unknown` comes
    /// before `invalidate`, which it also starts with.
    private static let supervisorPhrases: [(phrase: String, read: (@Sendable (Fields) -> SoakEvent?)?)] = [
        ("acquire new ", { $0.tag.map { .acquired($0, reused: false) } }),
        ("acquire reused ", { $0.tag.map { .acquired($0, reused: true) } }),
        ("invalidate unknown ", nil),
        ("invalidate ", { $0.tag.map { .invalidated($0) } }),
        ("torn down ", { $0.tag.map { .tornDown($0) } }),
        ("now showing ", { $0.tag.map { .shows($0, .playing) } }),
        ("holding still ", { $0.tag.map { .shows($0, .still) } }),
        ("showing nothing ", { $0.tag.map { .shows($0, .nothing) } }),
        ("update ", { fields in
            guard let tag = fields.tag, let mode = fields["mode"], ["desktop", "locked"].contains(mode) else { return nil }
            return .mode(tag, isLocked: mode == "locked")
        }),
        ("decision ", { fields in
            guard let display = fields["display"],
                  let decision = fields["decision"].flatMap(DisplayDecision.init(logged:)) else { return nil }
            return .decision(display: display, decision)
        }),
        ("check started ", { fields in
            guard let reason = fields["reason"], let surfaces = fields.int("surfaces") else { return nil }
            return .checkStarted(reason: reason, surfaces: surfaces)
        }),
        ("check count ", { fields in
            guard let tag = fields.tag, let displayed = fields.int("displayed"), let expected = fields.int("expected"),
                  let fed = fields.int("fed") else { return nil }
            let tally = PictureTally(
                displayed: displayed, expected: expected, fed: fed,
                asked: fields.int("asked"), presented: fields.int("presented"), withheld: fields.words.contains("withheld")
            )
            return .counted(tag, tally)
        }),
        ("check verdict ", { fields in
            guard let tag = fields.tag, let verdict = fields["verdict"].flatMap(CheckVerdict.init(logged:)),
                  let attempt = fields.int("attempt") else { return nil }
            return .verdict(tag, verdict, attempt: attempt)
        }),
        ("recovery tried ", { fields in
            guard let tag = fields.tag, let level = fields["level"].flatMap(LadderLevel.init(rawValue:)) else { return nil }
            return .recoveryTried(tag, level)
        }),
        ("restart requested ", { $0.tag.map { .restartRequested($0) } }),
        ("render state read ", nil),
        ("render state missing", nil),
        ("render state unreadable", nil),
        ("restart request cleared", nil),
        ("recover requested ", nil),
    ]

    private static func supervisor(_ message: Substring) -> Reading {
        guard let match = supervisorPhrases.first(where: { message.hasPrefix($0.phrase) }) else { return .unparsed }
        return match.read.map { event($0(Fields(message))) } ?? .known
    }

    /// A line the soak knows and does not count, when it is `lead` then one of `phrases`; otherwise unparsed.
    private static func known(_ message: Substring, after lead: String, startsWithOneOf phrases: [String]) -> Reading {
        phrases.contains { message.hasPrefix(lead + $0) } ? .known : .unparsed
    }

    private static func event(_ event: SoakEvent?) -> Reading {
        event.map(Reading.event) ?? .unparsed
    }
}

/// A line's `key=value` words, and the words that are not.
struct Fields {
    private var values: [Substring: String] = [:]
    private(set) var words: Set<Substring> = []

    init(_ message: Substring) {
        for word in message.split(separator: " ") {
            if let equals = word.firstIndex(of: "=") {
                values[word[..<equals]] = String(word[word.index(after: equals)...])
            } else {
                words.insert(word)
            }
        }
    }

    subscript(key: Substring) -> String? { values[key] }

    func int(_ key: Substring) -> Int? { values[key].flatMap { Int($0) } }

    /// `surface=… display=… preview=… wallpaper=… generation=…`.
    var tag: SurfaceTag? {
        guard let surface = values["surface"], let display = values["display"],
              let preview = values["preview"].flatMap(Bool.init), let wallpaper = values["wallpaper"],
              let generation = values["generation"] else { return nil }
        let number = UInt64(generation)
        guard number != nil || generation == "none" else { return nil }
        return SurfaceTag(
            surface: surface, display: display, isPreview: preview,
            wallpaper: wallpaper == "none" ? nil : wallpaper, generation: number
        )
    }
}

extension DisplayDecision {
    /// `play`, `pause.<reason>`, `suspend.<reason>`, `still` or `nothing`.
    init?(logged: String) {
        switch logged {
        case "play": self = .play
        case "still": self = .still
        case "nothing": self = .nothing
        default:
            if logged.hasPrefix("pause.") {
                self = .pause(String(logged.dropFirst("pause.".count)))
            } else if logged.hasPrefix("suspend.") {
                self = .suspend(String(logged.dropFirst("suspend.".count)))
            } else {
                return nil
            }
        }
    }
}

extension HostPhase {
    /// `RenderHostStatus.name`: `live`, `recovering(flush)`.
    init?(logged: Substring) {
        switch logged {
        case "stopped": self = .stopped
        case "connecting": self = .connecting
        case "notSelected": self = .notSelected
        case "live": self = .live
        case "unavailable": self = .unavailable
        default:
            guard logged.hasPrefix("recovering("), logged.hasSuffix(")"),
                  let level = LadderLevel(rawValue: String(logged.dropFirst("recovering(".count).dropLast())) else { return nil }
            self = .recovering(level)
        }
    }
}

extension CheckVerdict {
    init?(logged: String) {
        switch logged {
        case "healthy": self = .healthy
        case "notComposited": self = .notComposited
        default:
            guard let level = LadderLevel(rawValue: logged) else { return nil }
            self = .recover(level)
        }
    }
}
