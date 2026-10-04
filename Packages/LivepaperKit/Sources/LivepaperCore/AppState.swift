import Foundation

/// What the user has chosen that is not the library itself: the assignments,
/// playlists and rotations, the pause rules and pauses, mute, the grid's sort
/// order, the recents, the hotkeys and the login item's intent. The app writes
/// it as `app-state.json`, beside the manifest.
///
/// A value, like `Library`: every change returns a new state, so that undo can
/// keep the one from before.
public struct AppState: Equatable, Sendable {
    public static let schemaVersion = SchemaVersion(major: 1, minor: 1)
    /// How many wallpapers the recents keep.
    public static let recentsLimit = 8

    /// A display's own assignment, kept while it is unplugged.
    public var assignments: [DisplayIdentity: Assignment]
    /// What a display without its own assignment shows.
    public var applyToAll: Assignment?
    /// In the user's order.
    public var playlists: [Playlist]
    /// Where each display showing a playlist is in it, so that a shuffled pass survives a relaunch.
    public var rotation: [DisplayIdentity: RotationState]
    public var pauseRules: PauseRules
    /// The displays the user paused one at a time. Pause All is not remembered.
    public var pausedDisplays: Set<DisplayIdentity>
    /// Every display at volume 0, whatever its wallpaper's volume.
    public var isMuted: Bool
    public var sortOrder: Library.SortOrder
    /// The last wallpapers set on a display, newest first.
    public var recents: [WallpaperID]
    /// The global hotkeys the user assigned. They ship unassigned.
    public var hotkeys: [HotkeyAction: KeyCombination]
    /// What the user last asked of Open at Login, and the copy of Livepaper
    /// that asked; nil until they have been asked. The login item's status is
    /// macOS's, and `reconcileLoginItem` squares the two at every launch.
    public var loginItemIntent: LoginItemIntent?

    public init() {
        assignments = [:]
        applyToAll = nil
        playlists = []
        rotation = [:]
        pauseRules = PauseRules()
        pausedDisplays = []
        isMuted = false
        sortOrder = .newestFirst
        recents = []
        hotkeys = [:]
        loginItemIntent = nil
    }

    public subscript(playlist id: PlaylistID) -> Playlist? {
        playlists.first { $0.id == id }
    }

    /// What a display shows: `resolveAssignments` for this one display, so the rule is written once.
    public func assignment(for display: DisplayIdentity) -> Assignment? {
        resolveAssignments(assignments, connected: [display], applyToAll: applyToAll)[display]
    }

    /// Whether the display shows this wallpaper or playlist, by its own
    /// assignment or All Displays': Set on Display's checkmark.
    public func shows(_ assignment: Assignment, on display: DisplayIdentity) -> Bool {
        self.assignment(for: display) == assignment
    }

    // MARK: Set on display

    /// Sets a wallpaper or a playlist on these displays. A wallpaper goes first
    /// in the recents; a playlist starts afresh on each display, at once.
    public func assigning(
        _ assignment: Assignment, to displays: [DisplayIdentity], now: Date, rng: inout some RandomNumberGenerator
    ) -> AppState {
        guard !displays.isEmpty else { return self }
        var state = self
        for display in displays {
            state.assignments[display] = assignment
        }
        return state.startingAssignment(assignment, on: displays, after: self, now: now, rng: &rng)
    }

    /// All Displays: apply to all, and no display keeps one of its own, so that
    /// every display shows it, plugged in or not.
    public func assigningToAll(
        _ assignment: Assignment, connected: [DisplayIdentity], now: Date, rng: inout some RandomNumberGenerator
    ) -> AppState {
        var state = self
        state.applyToAll = assignment
        state.assignments = [:]
        return state.startingAssignment(assignment, on: connected, after: self, now: now, rng: &rng)
    }

    /// Takes away a display's own assignment: it shows apply to all, or nothing.
    public func unassigning(_ display: DisplayIdentity) -> AppState {
        var state = self
        state.assignments[display] = nil
        return state.keepingRotations(after: self)
    }

    /// The popover's playlist picker, for one display. A playlist starts on it,
    /// unless it is the one the display already shows. No Playlist (nil) keeps
    /// the wallpaper the display shows now as its own assignment, without
    /// putting it in the recents, since the user chose no wallpaper; a playlist
    /// with nothing to show leaves the display with no assignment of its own.
    public func choosingPlaylist(
        _ id: PlaylistID?, for display: DisplayIdentity, in library: Library, now: Date, rng: inout some RandomNumberGenerator
    ) -> AppState {
        if let id {
            guard self[playlist: id] != nil, assignment(for: display) != .playlist(id) else { return self }
            return assigning(.playlist(id), to: [display], now: now, rng: &rng)
        }
        guard case .playlist? = assignment(for: display) else { return self }
        guard let shown = wallpaper(shownOn: display, in: library) else { return unassigning(display) }
        var state = self
        state.assignments[display] = .wallpaper(shown.id)
        return state.keepingRotations(after: self)
    }

    /// One display's pause. The decoder is kept, so resuming is instant.
    public func settingPaused(_ paused: Bool, for display: DisplayIdentity) -> AppState {
        var state = self
        if paused {
            state.pausedDisplays.insert(display)
        } else {
            state.pausedDisplays.remove(display)
        }
        return state
    }

    // MARK: Next and Previous

    /// Moves on the playlist a display shows: Next, and the rotation driver's
    /// events. A display showing a wallpaper, or nothing, is left as it is.
    public func rotating(_ display: DisplayIdentity, _ event: RotationEvent, rng: inout some RandomNumberGenerator) -> AppState {
        guard let playlist = playlist(shownOn: display) else { return self }
        let (next, _) = nextRotation(playlist, (rotation[display] ?? RotationState()).settled(in: playlist), event, rng: &rng)
        var state = self
        state.rotation[display] = next
        return state
    }

    /// Previous: the display's rotation goes back to `wallpaper`, and the shuffled pass carries on.
    public func steppingBack(_ display: DisplayIdentity, to wallpaper: WallpaperID) -> AppState {
        guard let playlist = playlist(shownOn: display), let position = playlist.wallpapers.firstIndex(of: wallpaper) else { return self }
        var state = self
        var rotation = rotation[display] ?? RotationState()
        rotation.current = wallpaper
        rotation.position = position
        state.rotation[display] = rotation
        return state
    }

    // MARK: Delete

    /// A deleted wallpaper leaves everything that names it. A rotation showing
    /// it keeps its position, so that it carries on from the same place.
    public func removingWallpaper(_ id: WallpaperID) -> AppState {
        var state = self
        state.assignments = assignments.filter { $0.value != .wallpaper(id) }
        if applyToAll == .wallpaper(id) { state.applyToAll = nil }
        for index in state.playlists.indices {
            state.playlists[index].wallpapers.removeAll { $0 == id }
        }
        state.recents.removeAll { $0 == id }
        state.rotation = rotation.mapValues { rotation in
            var rotation = rotation
            rotation.upcoming.removeAll { $0 == id }
            if rotation.current == id { rotation.current = nil }
            return rotation
        }
        return state.keepingRotations(after: self)
    }

    // MARK: Playlists

    public func creatingPlaylist(_ playlist: Playlist) -> AppState {
        guard self[playlist: playlist.id] == nil else { return self }
        var state = self
        state.playlists.append(playlist)
        return state
    }

    /// A new playlist, last in the user's order, rotating every
    /// `Playlist.defaultInterval` in order. Its name is taken as a rename takes one.
    public func creatingPlaylist(_ id: PlaylistID, named name: String, with wallpapers: [WallpaperID]) throws -> AppState {
        guard let name = acceptedName(name) else { throw LibraryError.emptyName }
        return creatingPlaylist(Playlist(id: id, name: name, wallpapers: wallpapers, interval: Playlist.defaultInterval, shuffle: false))
    }

    /// Displays that showed it show apply to all, or nothing.
    public func deletingPlaylist(_ id: PlaylistID) -> AppState {
        var state = self
        state.playlists.removeAll { $0.id == id }
        state.assignments = assignments.filter { $0.value != .playlist(id) }
        if applyToAll == .playlist(id) { state.applyToAll = nil }
        return state.keepingRotations(after: self)
    }

    public func renamingPlaylist(_ id: PlaylistID, to name: String) throws -> AppState {
        guard let name = acceptedName(name) else { throw LibraryError.emptyName }
        return updatingPlaylist(id) { $0.name = name }
    }

    public func settingPlaylist(_ id: PlaylistID, interval: Duration) -> AppState {
        updatingPlaylist(id) { $0.interval = interval }
    }

    public func settingPlaylist(_ id: PlaylistID, shuffle: Bool) -> AppState {
        updatingPlaylist(id) { $0.shuffle = shuffle }
    }

    /// At the end, and once.
    public func adding(_ wallpaper: WallpaperID, toPlaylist id: PlaylistID) -> AppState {
        updatingPlaylist(id) { playlist in
            if !playlist.wallpapers.contains(wallpaper) { playlist.wallpapers.append(wallpaper) }
        }
    }

    public func removing(_ wallpaper: WallpaperID, fromPlaylist id: PlaylistID) -> AppState {
        updatingPlaylist(id) { $0.wallpapers.removeAll { $0 == wallpaper } }
    }

    // MARK: Helpers

    private func playlist(shownOn display: DisplayIdentity) -> Playlist? {
        guard case .playlist(let id)? = assignment(for: display) else { return nil }
        return self[playlist: id]
    }

    private func updatingPlaylist(_ id: PlaylistID, _ change: (inout Playlist) -> Void) -> AppState {
        guard let index = playlists.firstIndex(where: { $0.id == id }) else { return self }
        var state = self
        change(&state.playlists[index])
        return state
    }

    /// A rotation belongs to the playlist its display showed when it started: a
    /// display that now shows anything else loses it.
    private func keepingRotations(after before: AppState) -> AppState {
        var state = self
        state.rotation = rotation.filter { display, _ in
            guard case .playlist? = assignment(for: display) else { return false }
            return assignment(for: display) == before.assignment(for: display)
        }
        return state
    }

    /// After an assignment: a wallpaper goes first in the recents, and a playlist
    /// starts on these displays at its first wallpaper (in order) or the first of
    /// a shuffled pass.
    private func startingAssignment(
        _ assignment: Assignment, on displays: [DisplayIdentity], after before: AppState, now: Date,
        rng: inout some RandomNumberGenerator
    ) -> AppState {
        var state = keepingRotations(after: before)
        switch assignment {
        case .wallpaper(let id):
            state.recents.removeAll { $0 == id }
            state.recents.insert(id, at: 0)
            state.recents = Array(state.recents.prefix(Self.recentsLimit))
        case .playlist(let id):
            guard let playlist = self[playlist: id] else { break }
            for display in displays {
                state.rotation[display] = nextRotation(playlist, RotationState(), .next(at: now), rng: &rng).0
            }
        }
        return state
    }
}

// MARK: - Codec

extension AppState: Codable {
    private enum CodingKeys: String, CodingKey {
        case version, assignments, applyToAll, playlists, rotation, pauseRules, pausedDisplays, isMuted, sortOrder, recents
        case hotkeys, loginItemIntent
    }

    // Dictionaries are written as pairs sorted by display, so that the same state gives the same bytes.
    private struct DisplayAssignment: Codable {
        let display: DisplayIdentity
        let assignment: Assignment
    }

    private struct DisplayRotation: Codable {
        let display: DisplayIdentity
        let state: RotationState
    }

    // Hotkeys are written flat, the action beside its combination's fields, in the actions' order.
    private struct ActionHotkey: Codable {
        /// Raw, so that an action a newer minor version added is passed over, as its other new fields are.
        let action: String
        let keyCode: UInt16
        let modifiers: KeyCombination.Modifiers
        let keyLabel: String

        init(_ action: HotkeyAction, _ combination: KeyCombination) {
            self.action = action.rawValue
            keyCode = combination.keyCode
            modifiers = combination.modifiers
            keyLabel = combination.keyLabel
        }

        var combination: KeyCombination {
            KeyCombination(keyCode: keyCode, modifiers: modifiers, keyLabel: keyLabel)
        }
    }

    public func encode() throws -> Data {
        try PersistedJSON.encoder().encode(self)
    }

    /// Throws for anything it cannot fully trust, an unknown major version
    /// included. The store then keeps the file aside and the app starts on defaults.
    public static func decode(_ data: Data) throws -> AppState {
        try PersistedJSON.decoder().decode(AppState.self, from: data)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(SchemaVersion.self, forKey: .version)
        // When major version 2 arrives, version 1 is decoded here by a frozen
        // copy of this shape and migrated, and `app-state-v1.0.json` and
        // `app-state-v1.1.json` prove it.
        try version.requireReadable(by: Self.schemaVersion)

        let assignments = try container.decode([DisplayAssignment].self, forKey: .assignments)
        let rotation = try container.decode([DisplayRotation].self, forKey: .rotation)
        playlists = try container.decode([Playlist].self, forKey: .playlists)
        guard Set(assignments.map(\.display)).count == assignments.count,
              Set(rotation.map(\.display)).count == rotation.count else {
            throw DecodingError.dataCorruptedError(forKey: .assignments, in: container, debugDescription: "a display is listed twice")
        }
        guard Set(playlists.map(\.id)).count == playlists.count else {
            throw DecodingError.dataCorruptedError(forKey: .playlists, in: container, debugDescription: "two playlists share an identifier")
        }
        self.assignments = Dictionary(uniqueKeysWithValues: assignments.map { ($0.display, $0.assignment) })
        self.rotation = Dictionary(uniqueKeysWithValues: rotation.map { ($0.display, $0.state) })
        applyToAll = try container.decodeIfPresent(Assignment.self, forKey: .applyToAll)
        pauseRules = try container.decode(PauseRules.self, forKey: .pauseRules)
        pausedDisplays = Set(try container.decode([DisplayIdentity].self, forKey: .pausedDisplays))
        isMuted = try container.decode(Bool.self, forKey: .isMuted)
        sortOrder = try container.decode(Library.SortOrder.self, forKey: .sortOrder)
        recents = try container.decode([WallpaperID].self, forKey: .recents)
        // Version 1.1's: a 1.0 file has neither.
        let hotkeys = try container.decodeIfPresent([ActionHotkey].self, forKey: .hotkeys) ?? []
        guard Set(hotkeys.map(\.action)).count == hotkeys.count else {
            throw DecodingError.dataCorruptedError(forKey: .hotkeys, in: container, debugDescription: "an action is listed twice")
        }
        self.hotkeys = Dictionary(uniqueKeysWithValues: hotkeys.compactMap { hotkey in
            HotkeyAction(rawValue: hotkey.action).map { ($0, hotkey.combination) }
        })
        loginItemIntent = try container.decodeIfPresent(LoginItemIntent.self, forKey: .loginItemIntent)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaVersion, forKey: .version)
        try container.encode(
            assignments.sorted(byDisplay: \.key).map { DisplayAssignment(display: $0.key, assignment: $0.value) }, forKey: .assignments
        )
        try container.encodeIfPresent(applyToAll, forKey: .applyToAll)
        try container.encode(playlists, forKey: .playlists)
        try container.encode(rotation.sorted(byDisplay: \.key).map { DisplayRotation(display: $0.key, state: $0.value) }, forKey: .rotation)
        try container.encode(pauseRules, forKey: .pauseRules)
        try container.encode(pausedDisplays.sorted(byDisplay: \.self), forKey: .pausedDisplays)
        try container.encode(isMuted, forKey: .isMuted)
        try container.encode(sortOrder, forKey: .sortOrder)
        try container.encode(recents, forKey: .recents)
        let hotkeys = HotkeyAction.allCases.compactMap { action in self.hotkeys[action].map { ActionHotkey(action, $0) } }
        try container.encode(hotkeys, forKey: .hotkeys)
        try container.encodeIfPresent(loginItemIntent, forKey: .loginItemIntent)
    }
}

extension Sequence {
    /// In the order of the displays' UUID strings, the one order every file uses.
    func sorted(byDisplay display: (Element) -> DisplayIdentity) -> [Element] {
        sorted { display($0).description < display($1).description }
    }
}
