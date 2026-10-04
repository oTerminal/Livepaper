import Foundation

/// What `status` answers over the command socket: the host's status, the
/// displays and what each shows, the library's wallpapers and playlists by ID
/// and name, Pause All and mute. The `livepaper` tool prints it, and resolves
/// `set <name>` against it.
public struct StatusReport: Equatable, Sendable {
    public struct Display: Codable, Equatable, Sendable {
        public var id: DisplayIdentity
        /// As macOS names it: "Built-in Retina Display".
        public var name: String
        /// What it shows: its own assignment or All Displays', nil for nothing.
        public var assignment: Assignment?
        /// Paused on its own. Pause All is the report's.
        public var isPaused: Bool

        public init(id: DisplayIdentity, name: String, assignment: Assignment?, isPaused: Bool) {
            self.id = id
            self.name = name
            self.assignment = assignment
            self.isPaused = isPaused
        }
    }

    /// A wallpaper or a playlist, by its ID and its name.
    public struct Named<ID: Codable & Hashable & Sendable>: Codable, Equatable, Sendable {
        public var id: ID
        public var name: String

        public init(id: ID, name: String) {
            self.id = id
            self.name = name
        }
    }

    public var host: RenderHostStatus
    /// In the order of their UUIDs, the one order every file uses.
    public var displays: [Display]
    /// In the order they were imported.
    public var wallpapers: [Named<WallpaperID>]
    /// In the user's order.
    public var playlists: [Named<PlaylistID>]
    public var isPausedAll: Bool
    public var isMuted: Bool

    public init(
        host: RenderHostStatus,
        displays: [Display],
        wallpapers: [Named<WallpaperID>],
        playlists: [Named<PlaylistID>],
        isPausedAll: Bool,
        isMuted: Bool
    ) {
        self.host = host
        self.displays = displays.sorted(byDisplay: \.id)
        self.wallpapers = wallpapers
        self.playlists = playlists
        self.isPausedAll = isPausedAll
        self.isMuted = isMuted
    }

    /// The report for the connected displays, named as macOS names them, from
    /// the library and the app state. Pause All is not in the app state, so it is given.
    public init(host: RenderHostStatus, displays names: [DisplayIdentity: String], library: Library, state: AppState, isPausedAll: Bool) {
        self.init(
            host: host,
            displays: names.map { identity, name in
                Display(
                    id: identity,
                    name: name,
                    assignment: state.assignment(for: identity),
                    isPaused: state.pausedDisplays.contains(identity)
                )
            },
            wallpapers: library.wallpapers.map { Named(id: $0.id, name: $0.name) },
            playlists: state.playlists.map { Named(id: $0.id, name: $0.name) },
            isPausedAll: isPausedAll,
            isMuted: state.isMuted
        )
    }
}

// MARK: - Codec

extension StatusReport: Codable {
    private enum CodingKeys: String, CodingKey {
        case host, displays, wallpapers, playlists, isPausedAll, isMuted
    }

    /// One line of JSON, its keys sorted, so that the same report gives the same bytes.
    public func encoded() throws -> Data {
        try CommandJSON.encoder().encode(self)
    }

    public static func decode(_ data: Data) throws -> StatusReport {
        try JSONDecoder().decode(StatusReport.self, from: data)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let host = try container.decode(String.self, forKey: .host)
        guard let status = Self.hostStatuses.first(where: { $0.name == host }) else {
            throw DecodingError.dataCorruptedError(forKey: .host, in: container, debugDescription: "not a host status: \(host)")
        }
        self.host = status
        displays = try container.decode([Display].self, forKey: .displays)
        wallpapers = try container.decode([Named<WallpaperID>].self, forKey: .wallpapers)
        playlists = try container.decode([Named<PlaylistID>].self, forKey: .playlists)
        isPausedAll = try container.decode(Bool.self, forKey: .isPausedAll)
        isMuted = try container.decode(Bool.self, forKey: .isMuted)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(host.name, forKey: .host)
        try container.encode(displays, forKey: .displays)
        try container.encode(wallpapers, forKey: .wallpapers)
        try container.encode(playlists, forKey: .playlists)
        try container.encode(isPausedAll, forKey: .isPausedAll)
        try container.encode(isMuted, forKey: .isMuted)
    }

    private static let hostStatuses: [RenderHostStatus] =
        [.stopped, .connecting, .notSelected, .live, .unavailable] + RecoveryLevel.allCases.map { .recovering($0) }
}

// MARK: - The reply

/// What the app answers on the command socket: one line of JSON, then it
/// closes. `ok` says whether it was done; a refusal carries the reason, which
/// the tool prints.
public enum CommandReply: Equatable, Sendable {
    /// `{"ok":true}`, with what was done in words when there is something to say.
    case done(message: String?)
    /// `{"ok":true,"status":{…}}`
    case status(StatusReport)
    /// `{"ok":true,"diagnostics":"…"}`: the report as it would go on the clipboard.
    case diagnostics(String)
    /// `{"ok":false,"reason":"…"}`: a rejected command, or one the app would not run.
    case refused(reason: String)

    public static func refused(_ rejection: CommandRejection) -> CommandReply {
        .refused(reason: rejection.reason)
    }

    /// The reply's line: JSON with its keys sorted, then a line feed. Line breaks inside it are escaped.
    public func line() throws -> Data {
        try CommandJSON.encoder().encode(self) + Data("\n".utf8)
    }

    public init(line: Data) throws {
        self = try JSONDecoder().decode(CommandReply.self, from: line)
    }
}

extension CommandReply: Codable {
    private enum CodingKeys: String, CodingKey {
        case ok, message, status, diagnostics, reason
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard try container.decode(Bool.self, forKey: .ok) else {
            self = .refused(reason: try container.decode(String.self, forKey: .reason))
            return
        }
        let status = try container.decodeIfPresent(StatusReport.self, forKey: .status)
        let diagnostics = try container.decodeIfPresent(String.self, forKey: .diagnostics)
        switch (status, diagnostics) {
        case (let status?, nil): self = .status(status)
        case (nil, let diagnostics?): self = .diagnostics(diagnostics)
        case (nil, nil): self = .done(message: try container.decodeIfPresent(String.self, forKey: .message))
        case (.some, .some):
            throw DecodingError.dataCorruptedError(
                forKey: .status, in: container, debugDescription: "a reply carries a status or diagnostics, not both"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .done(let message):
            try container.encode(true, forKey: .ok)
            try container.encodeIfPresent(message, forKey: .message)
        case .status(let report):
            try container.encode(true, forKey: .ok)
            try container.encode(report, forKey: .status)
        case .diagnostics(let text):
            try container.encode(true, forKey: .ok)
            try container.encode(text, forKey: .diagnostics)
        case .refused(let reason):
            try container.encode(false, forKey: .ok)
            try container.encode(reason, forKey: .reason)
        }
    }
}

/// The socket's JSON: compact, so that a reply is one line, and sorted.
enum CommandJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }
}
