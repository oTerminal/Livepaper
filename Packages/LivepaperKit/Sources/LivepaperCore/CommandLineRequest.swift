import Foundation

/// What the `livepaper` tool's arguments ask the app, worked out before
/// anything is sent. The tool sends the command's URL over the socket and
/// prints the reply; it reads no file and writes none.
public enum CommandLineRequest: Hashable, Sendable {
    case help
    /// `status`, printed readably, or as the report's JSON.
    case status(json: Bool)
    /// `set <name-or-UUID>`: `status` is asked first, and the name resolved
    /// against it with `StatusReport.assignment(named:)`, since the URL names
    /// a wallpaper or a playlist by ID.
    case set(String, on: DisplayTarget)
    /// Every other command, sent as it is.
    case send(Command)

    public static let usage = """
        usage: livepaper <command> [options]

        Commands:
          status [--json]                        What Livepaper shows, and the library's wallpapers and playlists
          set <name-or-UUID> [--display <UUID>]  Show a wallpaper or a playlist on every display, or on one
          pause [--display <UUID>]               Pause every display, or one
          resume [--display <UUID>]              Play again
          next [--display <UUID>]                Move a display's playlist on to its next wallpaper
          mute                                   Silence every wallpaper
          unmute                                 Let wallpapers play their sound again
          library                                Open the library window
          settings                               Open Settings
          diagnostics                            Print the diagnostics report
          help                                   Show this

        A display is named by a UUID that `livepaper status` lists, or `all`. A
        name that more than one wallpaper or playlist has is refused: use the UUID.
        Wallpapers are imported in Livepaper's window, not here.
        Livepaper is opened when it is not running, unless LIVEPAPER_NO_LAUNCH is set.

        Exit status: 0 done, 1 refused, 2 usage, 3 Livepaper could not be reached.
        """

    /// The request the arguments make, the command's name first.
    public init(arguments: [String]) throws(CommandLineUsageError) {
        guard let name = arguments.first else { throw .noCommand }
        if ["help", "-h", "--help"].contains(name) {
            self = .help
            return
        }
        var parsed = try ParsedArguments(command: name, arguments.dropFirst())
        switch name {
        case "status":
            let json = try parsed.flag("--json")
            try parsed.finish(positionals: 0)
            self = .status(json: json)
        case "set":
            let target = try parsed.display()
            try parsed.finish(positionals: 1)
            guard let assignment = parsed.positionals.first else { throw .noName }
            guard acceptedName(assignment) != nil else { throw .emptyArgument }
            self = .set(assignment, on: target)
        case "pause", "resume", "next":
            let target = try parsed.display()
            try parsed.finish(positionals: 0)
            self = .send(name == "pause" ? .pause(target) : name == "resume" ? .resume(target) : .next(target))
        default:
            guard let command = Self.plainCommands[name] else { throw .unknownCommand(name) }
            try parsed.finish(positionals: 0)
            self = .send(command)
        }
    }

    /// The commands that take nothing.
    private static let plainCommands: [String: Command] = [
        "mute": .mute, "unmute": .unmute, "library": .library, "settings": .settings, "diagnostics": .diagnostics,
    ]
}

/// What was wrong with the arguments. The tool prints `message` and the usage, and exits with status 2.
public enum CommandLineUsageError: Error, Hashable, Sendable {
    case noCommand
    case unknownCommand(String)
    case noName
    case emptyArgument
    case unknownOption(command: String, option: String)
    case repeatedOption(String)
    case missingValue(String)
    case unexpectedArgument(command: String, argument: String)
    case notADisplay(String)

    public var message: String {
        switch self {
        case .noCommand: "No command given"
        case .unknownCommand(let name): "“\(name)” is not a command"
        case .noName: "set needs the name or UUID of a wallpaper or a playlist"
        case .emptyArgument: "An argument is empty"
        case .unknownOption(let command, let option): "\(command) does not take \(option)"
        case .repeatedOption(let option): "\(option) is given more than once"
        case .missingValue(let option): "\(option) needs a value"
        case .unexpectedArgument(let command, let argument): "\(command) does not take “\(argument)”"
        case .notADisplay(let value): "“\(value)” is not a display's UUID or “all”"
        }
    }
}

/// The arguments after the command's name: the options, taken as the command
/// asks for them, and the rest.
private struct ParsedArguments {
    /// Options followed by a value, when it is not given after `=`.
    private static let takingValues: Set<String> = ["--display"]

    let command: String
    private(set) var positionals: [String] = []
    private var options: [(name: String, value: String?)] = []

    init(command: String, _ arguments: ArraySlice<String>) throws(CommandLineUsageError) {
        self.command = command
        var remaining = arguments
        var afterSeparator = false
        while let argument = remaining.popFirst() {
            if afterSeparator || !argument.hasPrefix("-") || argument == "-" {
                positionals.append(argument)
            } else if argument == "--" {
                afterSeparator = true
            } else if let equals = argument.firstIndex(of: "=") {
                options.append((String(argument[..<equals]), String(argument[argument.index(after: equals)...])))
            } else if Self.takingValues.contains(argument) {
                guard let value = remaining.popFirst() else { throw .missingValue(argument) }
                options.append((argument, value))
            } else {
                options.append((argument, nil))
            }
        }
    }

    /// Whether a flag was given.
    mutating func flag(_ name: String) throws(CommandLineUsageError) -> Bool {
        guard let option = try take(name) else { return false }
        if let value = option.value { throw .unexpectedArgument(command: command, argument: "\(name)=\(value)") }
        return true
    }

    /// `--display <UUID>`, or `all`, which is also what no `--display` means.
    mutating func display() throws(CommandLineUsageError) -> DisplayTarget {
        guard let option = try take("--display") else { return .all }
        let value = option.value ?? ""
        if value == "all" { return .all }
        guard let uuid = UUID(uuidString: value) else { throw .notADisplay(value) }
        return .display(DisplayIdentity(uuid: uuid))
    }

    /// Nothing is left but up to `limit` positional arguments.
    func finish(positionals limit: Int) throws(CommandLineUsageError) {
        if let option = options.first { throw .unknownOption(command: command, option: option.name) }
        if positionals.count > limit { throw .unexpectedArgument(command: command, argument: positionals[limit]) }
    }

    private mutating func take(_ name: String) throws(CommandLineUsageError) -> (name: String, value: String?)? {
        let given = options.filter { $0.name == name }
        guard given.count <= 1 else { throw .repeatedOption(name) }
        options.removeAll { $0.name == name }
        return given.first
    }
}

// MARK: - Resolving a name

/// Why `set <name>` cannot say which wallpaper or playlist it means. The tool
/// prints `reason` and exits with status 1, as for a refusal.
public enum AssignmentNameError: Error, Hashable, Sendable {
    case notFound(String)
    /// Every wallpaper and playlist it could mean, wallpapers first.
    case ambiguous(String, [Assignment])

    public var reason: String {
        switch self {
        case .notFound(let name):
            return "No wallpaper or playlist is called “\(name)”"
        case .ambiguous(let name, let candidates):
            let uuids = candidates.map { candidate in
                switch candidate {
                case .wallpaper(let id): "wallpaper \(id)"
                case .playlist(let id): "playlist \(id)"
                }
            }
            return "“\(name)” names more than one thing; use a UUID: " + uuids.joined(separator: ", ")
        }
    }
}

extension StatusReport {
    /// The wallpaper or playlist `set <name-or-UUID>` means. A UUID is looked
    /// up among the IDs; a name, without the spaces around it, is matched whole
    /// against wallpapers and playlists alike: exactly first, then ignoring case
    /// and accents. The first rule with any match decides, and it must match one
    /// thing only: a name two things share is refused with their UUIDs, never guessed.
    public func assignment(named typed: String) throws(AssignmentNameError) -> Assignment {
        let name = acceptedName(typed) ?? typed
        if let uuid = UUID(uuidString: name) {
            if wallpapers.contains(where: { $0.id.uuid == uuid }) { return .wallpaper(WallpaperID(uuid: uuid)) }
            if playlists.contains(where: { $0.id.uuid == uuid }) { return .playlist(PlaylistID(uuid: uuid)) }
            throw .notFound(name)
        }
        let rules: [(String) -> Bool] = [
            { $0 == name },
            { $0.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame },
        ]
        for matches in rules {
            let found = wallpapers.filter { matches($0.name) }.map { Assignment.wallpaper($0.id) }
                + playlists.filter { matches($0.name) }.map { Assignment.playlist($0.id) }
            if found.count == 1, let only = found.first { return only }
            if found.count > 1 { throw .ambiguous(name, found) }
        }
        throw .notFound(name)
    }
}

// MARK: - Printing the reply

/// How the tool ends.
public enum CommandLineExit: Int32, Sendable {
    case done = 0
    /// The app refused the command, or `set` named nothing it has.
    case refused = 1
    case usage = 2
    /// No app answered on the socket, even after opening it.
    case unreachable = 3
}

/// What the tool prints for a reply, and how it exits.
public struct CommandLineOutput: Hashable, Sendable {
    public var standardOutput: String
    public var standardError: String
    public var exit: CommandLineExit

    public init(standardOutput: String, standardError: String, exit: CommandLineExit) {
        self.standardOutput = standardOutput
        self.standardError = standardError
        self.exit = exit
    }

    /// Words go to standard output, a line each; a refusal to standard error.
    /// `status` is printed readably, or with `json` as the report's JSON line.
    public init(_ reply: CommandReply, json: Bool) {
        switch reply {
        case .done(let message):
            self.init(standardOutput: message.map { Self.line($0) } ?? "", standardError: "", exit: .done)
        case .status(let report):
            let text = json ? (try? report.encoded()).flatMap { String(bytes: $0, encoding: .utf8) } ?? "" : report.readable
            self.init(standardOutput: Self.line(text), standardError: "", exit: .done)
        case .diagnostics(let text):
            self.init(standardOutput: Self.line(text), standardError: "", exit: .done)
        case .refused(let reason):
            self.init(refusal: reason)
        }
    }

    /// A refusal that is the tool's own: a name `set` could not resolve.
    public init(refusal reason: String) {
        self.init(standardOutput: "", standardError: "livepaper: " + Self.line(reason), exit: .refused)
    }

    private static func line(_ text: String) -> String {
        text.hasSuffix("\n") ? text : text + "\n"
    }
}

extension StatusReport {
    /// The report as the tool prints it: the host, Pause All and mute, then a
    /// line per display, wallpaper and playlist, each with the UUID the other
    /// commands take.
    var readable: String {
        var lines = [
            "Status: \(host.words)",
            "Pause All: \(isPausedAll ? "on" : "off")",
            "Mute: \(isMuted ? "on" : "off")",
            "",
            "Displays",
        ]
        lines += displays.isEmpty ? ["  none"] : displays.map { display in
            "  \(display.id)  \(display.name): \(shows(display.assignment))\(display.isPaused ? ", paused" : "")"
        }
        lines += ["", "Wallpapers"] + Self.list(wallpapers)
        lines += ["", "Playlists"] + Self.list(playlists)
        return lines.joined(separator: "\n")
    }

    private func shows(_ assignment: Assignment?) -> String {
        switch assignment {
        case .wallpaper(let id)?: "wallpaper “\(wallpapers.first { $0.id == id }?.name ?? id.description)”"
        case .playlist(let id)?: "playlist “\(playlists.first { $0.id == id }?.name ?? id.description)”"
        case nil: "nothing"
        }
    }

    private static func list<ID>(_ named: [Named<ID>]) -> [String] {
        named.isEmpty ? ["  none"] : named.map { "  \($0.id)  \($0.name)" }
    }
}
