import Foundation

/// An ordered set of wallpapers that a display rotates through.
public struct Playlist: Equatable, Identifiable, Sendable {
    /// What a new playlist waits between rotations.
    public static let defaultInterval: Duration = .seconds(30 * 60)
    /// A second to a year: what `app-state.json` may say, since it can be edited
    /// by hand. Nothing shorter rotates, and a number too large for a `Duration` traps.
    public static let intervalLimits: ClosedRange<Duration> = .seconds(1) ... .seconds(365 * 24 * 60 * 60)

    public let id: PlaylistID
    public var name: String
    public var wallpapers: [WallpaperID]
    /// How long each wallpaper shows before a tick moves on.
    public var interval: Duration
    public var shuffle: Bool

    public init(id: PlaylistID, name: String, wallpapers: [WallpaperID], interval: Duration, shuffle: Bool) {
        self.id = id
        self.name = name
        self.wallpapers = wallpapers
        self.interval = interval
        self.shuffle = shuffle
    }

    /// What the inspector offers: 5, 15 and 30 minutes, an hour, 3 hours and a
    /// day, and the playlist's own interval among them, in order, when it is none of those.
    public static func intervalChoices(including current: Duration) -> [Duration] {
        let choices: [Duration] = [5, 15, 30, 60, 180, 1440].map { .seconds($0 * 60) }
        return choices.contains(current) ? choices : (choices + [current]).sorted()
    }
}

/// Where one display is in its playlist.
public struct RotationState: Equatable, Sendable {
    /// The wallpaper the playlist last chose.
    public var current: WallpaperID?
    /// Where `current` was in the playlist when it was chosen, so that rotation
    /// can carry on from the same place after `current` is deleted.
    public var position: Int?
    /// The rest of the shuffled pass.
    public var upcoming: [WallpaperID]
    public var lastRotation: Date?

    public init(current: WallpaperID? = nil, position: Int? = nil, upcoming: [WallpaperID] = [], lastRotation: Date? = nil) {
        self.current = current
        self.position = position
        self.upcoming = upcoming
        self.lastRotation = lastRotation
    }
}

/// What can move a playlist on. Each carries its time: Core never reads the clock.
public enum RotationEvent: Equatable, Sendable {
    /// The rotation timer fired. Rotates only once the playlist's interval has passed.
    case tick(at: Date)
    case wake(at: Date)
    case login(at: Date)
    /// The user asked for the next wallpaper. On a playlist that has not
    /// started, that is its first: in order, the first in the list.
    case next(at: Date)

    var date: Date {
        switch self {
        case .tick(let date), .wake(let date), .login(let date), .next(let date): date
        }
    }
}

/// Moves a playlist on. Returns the new state and the wallpaper to switch to,
/// or `nil` when the display should keep what it shows.
public func nextRotation(
    _ playlist: Playlist, _ state: RotationState, _ event: RotationEvent, rng: inout some RandomNumberGenerator
) -> (RotationState, WallpaperID?) {
    // A tick waits for the interval, unless what is showing has been deleted.
    let currentIsGone = state.current.map { !playlist.wallpapers.contains($0) } ?? false
    if case .tick(let now) = event, let last = state.lastRotation, !currentIsGone,
       now.elapsed(since: last) < playlist.interval {
        return (state, nil)
    }

    var next = state
    next.lastRotation = event.date
    // Wallpapers deleted since the pass was shuffled are never shown.
    next.upcoming = state.upcoming.filter(playlist.wallpapers.contains)

    guard let chosen = playlist.shuffle ? next.drawShuffled(from: playlist, rng: &rng) : next.following(in: playlist) else {
        return (next, nil)
    }
    next.position = playlist.wallpapers.firstIndex(of: chosen)
    guard chosen != state.current else { return (next, nil) }
    next.current = chosen
    return (next, chosen)
}

extension RotationState {
    /// What a display showing this playlist shows: `current` while the playlist
    /// has it, else the entry now at `position` (the one that followed a deleted
    /// `current`), else the first, passing over any `isAvailable` refuses.
    func showing(in playlist: Playlist, where isAvailable: (WallpaperID) -> Bool = { _ in true }) -> WallpaperID? {
        let wallpapers = playlist.wallpapers
        let start = current.flatMap(wallpapers.firstIndex(of:)) ?? position ?? 0
        return wallpapers.indices.lazy.map { wallpapers[(start + $0) % wallpapers.count] }.first(where: isAvailable)
    }

    /// The state as the display shows it, so that a rotation moves on from what
    /// is on screen rather than from a wallpaper that has gone.
    func settled(in playlist: Playlist) -> RotationState {
        guard let shown = showing(in: playlist), shown != current else { return self }
        var settled = self
        settled.current = shown
        settled.position = playlist.wallpapers.firstIndex(of: shown)
        settled.upcoming.removeAll { $0 == shown }
        return settled
    }

    /// In order: the wallpaper after the current one, wrapping. When the current
    /// one has been deleted, its old position now holds the one that followed it.
    fileprivate func following(in playlist: Playlist) -> WallpaperID? {
        let wallpapers = playlist.wallpapers
        guard !wallpapers.isEmpty else { return nil }
        if let current, let index = wallpapers.firstIndex(of: current) {
            return wallpapers[(index + 1) % wallpapers.count]
        }
        guard let position else { return wallpapers[0] }
        return wallpapers[position % wallpapers.count]
    }

    /// Shuffled: the next wallpaper of the pass. A new pass is shuffled when the
    /// last one runs out, and never starts with the wallpaper that is showing.
    fileprivate mutating func drawShuffled(from playlist: Playlist, rng: inout some RandomNumberGenerator) -> WallpaperID? {
        if upcoming.isEmpty {
            upcoming = shuffled(playlist.wallpapers, rng: &rng)
            if upcoming.count > 1, upcoming[0] == current {
                upcoming.swapAt(0, 1 + index(below: upcoming.count - 1, rng: &rng))
            }
        }
        return upcoming.isEmpty ? nil : upcoming.removeFirst()
    }
}

// Fisher-Yates, written out rather than `shuffled(using:)` so that a seed gives
// the same order on every toolchain. The modulo bias is below 2^-50 for any
// playlist that fits in memory.
private func shuffled(_ wallpapers: [WallpaperID], rng: inout some RandomNumberGenerator) -> [WallpaperID] {
    var result = wallpapers
    for last in stride(from: result.count - 1, to: 0, by: -1) {
        result.swapAt(last, index(below: last + 1, rng: &rng))
    }
    return result
}

private func index(below bound: Int, rng: inout some RandomNumberGenerator) -> Int {
    Int(rng.next() % UInt64(bound))
}

// MARK: - Codec

extension Playlist: Codable {
    private enum CodingKeys: String, CodingKey {
        case id, name, wallpapers, interval, shuffle
    }

    // The interval is written in seconds, a plain number anyone can read and edit,
    // and is checked against `intervalLimits` before it becomes a `Duration`.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(PlaylistID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        wallpapers = try container.decode([WallpaperID].self, forKey: .wallpapers)
        let seconds = try container.decode(Double.self, forKey: .interval)
        let limits = Self.intervalLimits
        guard seconds.isFinite, seconds >= limits.lowerBound / .seconds(1), seconds <= limits.upperBound / .seconds(1) else {
            throw DecodingError.dataCorruptedError(
                forKey: .interval, in: container, debugDescription: "an interval of \(seconds) s is outside \(limits)"
            )
        }
        interval = .seconds(seconds)
        shuffle = try container.decode(Bool.self, forKey: .shuffle)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(wallpapers, forKey: .wallpapers)
        try container.encode(interval / .seconds(1), forKey: .interval)
        try container.encode(shuffle, forKey: .shuffle)
    }
}

// A rotation that has not started has no current, position or last rotation,
// and those keys are left out.
extension RotationState: Codable {
    private enum CodingKeys: String, CodingKey {
        case current, position, upcoming, lastRotation
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        current = try container.decodeIfPresent(WallpaperID.self, forKey: .current)
        position = try container.decodeIfPresent(Int.self, forKey: .position)
        upcoming = try container.decodeIfPresent([WallpaperID].self, forKey: .upcoming) ?? []
        lastRotation = try container.decodeIfPresent(Date.self, forKey: .lastRotation)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(current, forKey: .current)
        try container.encodeIfPresent(position, forKey: .position)
        try container.encode(upcoming, forKey: .upcoming)
        try container.encodeIfPresent(lastRotation, forKey: .lastRotation)
    }
}
