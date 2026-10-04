import Foundation

/// A row of the library window's sidebar.
public enum LibrarySection: Hashable, Sendable {
    case all
    case favourites
    case playlist(PlaylistID)
    /// What a connected display shows: its wallpaper, or its playlist's wallpapers.
    case nowPlaying(DisplayIdentity)
}

/// The sidebar's counts.
public struct SidebarCounts: Equatable, Sendable {
    public var all: Int
    public var favourites: Int
    /// Only the wallpapers still in the library.
    public var playlists: [PlaylistID: Int]

    public init(all: Int, favourites: Int, playlists: [PlaylistID: Int]) {
        self.all = all
        self.favourites = favourites
        self.playlists = playlists
    }
}

public func sidebarCounts(library: Library, state: AppState) -> SidebarCounts {
    SidebarCounts(
        all: library.wallpapers.count,
        favourites: library.favourites.count,
        playlists: Dictionary(uniqueKeysWithValues: state.playlists.map { playlist in
            (playlist.id, playlist.wallpapers.count { library[$0] != nil })
        })
    )
}

/// The grid: the section's wallpapers that match the search, by `Library.search`'s
/// rule, in the state's sort order. A playlist, and a display's playlist, keeps
/// the user's order instead.
public func libraryGrid(library: Library, state: AppState, section: LibrarySection, search: String) -> [Wallpaper] {
    let found = library.search(search)
    let matching = Set(found.map(\.id))
    func inOrder(_ ids: [WallpaperID]) -> [Wallpaper] {
        ids.filter(matching.contains).compactMap { library[$0] }
    }

    switch section {
    case .all:
        return found.sorted(by: state.sortOrder)
    case .favourites:
        return found.filter(\.isFavourite).sorted(by: state.sortOrder)
    case .playlist(let id):
        return inOrder(state[playlist: id]?.wallpapers ?? [])
    case .nowPlaying(let display):
        switch state.assignment(for: display) {
        case .wallpaper(let id)?: return inOrder([id])
        case .playlist(let id)?: return inOrder(state[playlist: id]?.wallpapers ?? [])
        case nil: return []
        }
    }
}

extension LibrarySection {
    /// Whether the grid follows the sort order: a playlist keeps the user's
    /// order, and so does a display showing one.
    public var followsSortOrder: Bool {
        switch self {
        case .all, .favourites: true
        case .playlist, .nowPlaying: false
        }
    }

    /// The section once displays or playlists have come or gone: All, when its
    /// display is unplugged or its playlist deleted.
    public func resolved(displays: [DisplayIdentity], playlists: [Playlist]) -> LibrarySection {
        switch self {
        case .all, .favourites: self
        case .playlist(let id): playlists.contains { $0.id == id } ? self : .all
        case .nowPlaying(let display): displays.contains(display) ? self : .all
        }
    }

    /// Where the sidebar goes when `playlist` is made: to it when it is empty,
    /// since it is filled from there; one made from a wallpaper's menu, with that
    /// wallpaper in it, leaves the user where they were.
    public func afterCreating(_ playlist: Playlist) -> LibrarySection {
        playlist.wallpapers.isEmpty ? .playlist(playlist.id) : self
    }
}

/// Why the grid shows nothing, for the window's empty state.
public enum EmptyGrid: Equatable, Sendable {
    /// The library has none, whatever the section: Import is the way on.
    case noWallpapers
    case noFavourites
    /// The playlist has no wallpaper the library still has.
    case emptyPlaylist(PlaylistID)
    /// The display shows nothing: it has no assignment, or what it has is lost or empty.
    case nothingOnDisplay(DisplayIdentity)
    /// The section has wallpapers and none matches the search, as typed without
    /// the spaces around it. A section that is empty anyway says so instead,
    /// since clearing the search would not help.
    case noResults(search: String)
}

/// Nil while the grid (`libraryGrid`) shows a wallpaper.
public func emptyGrid(library: Library, state: AppState, section: LibrarySection, search: String) -> EmptyGrid? {
    guard !library.wallpapers.isEmpty else { return .noWallpapers }
    guard libraryGrid(library: library, state: state, section: section, search: search).isEmpty else { return nil }
    guard libraryGrid(library: library, state: state, section: section, search: "").isEmpty else {
        return .noResults(search: search.trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return switch section {
    case .all: .noWallpapers
    case .favourites: .noFavourites
    case .playlist(let id): .emptyPlaylist(id)
    case .nowPlaying(let display): .nothingOnDisplay(display)
    }
}

/// The one selected tile in the grid: a click selects it, the arrows move it,
/// and Delete deletes it.
public struct GridSelection: Equatable, Sendable {
    public enum Move: Sendable {
        case left, right, up, down, first, last
    }

    public private(set) var selected: WallpaperID?

    public init(selected: WallpaperID? = nil) {
        self.selected = selected
    }

    public mutating func click(_ id: WallpaperID) {
        selected = id
    }

    /// Moves over a grid of `columns` tiles to a row. Left and right run on
    /// across rows, and nothing wraps past either end. Down onto a short last
    /// row with no tile below goes to its last tile. From no selection, an arrow
    /// selects the first tile, and `.last` the last.
    public mutating func move(_ move: Move, in grid: [WallpaperID], columns: Int) {
        guard let lastIndex = grid.indices.last else {
            selected = nil
            return
        }
        guard let index = selected.flatMap(grid.firstIndex(of:)) else {
            selected = move == .last ? grid[lastIndex] : grid[0]
            return
        }
        let columns = max(columns, 1)
        let target = switch move {
        case .left: max(index - 1, 0)
        case .right: min(index + 1, lastIndex)
        case .up: index >= columns ? index - columns : index
        case .down: index + columns <= lastIndex ? index + columns : (index / columns < lastIndex / columns ? lastIndex : index)
        case .first: 0
        case .last: lastIndex
        }
        selected = grid[target]
    }

    /// After a wallpaper is deleted from `grid`, the grid as it was: a selected
    /// wallpaper gives way to the one that followed it, else the one before.
    public mutating func deleted(_ id: WallpaperID, from grid: [WallpaperID]) {
        guard selected == id else { return }
        guard let index = grid.firstIndex(of: id) else {
            selected = nil
            return
        }
        selected = grid.indices.contains(index + 1) ? grid[index + 1] : (index > 0 ? grid[index - 1] : nil)
    }

    /// The grid changed (search, section, sort): the selection stays while it is in it.
    public mutating func gridChanged(_ grid: [WallpaperID]) {
        if let selected, !grid.contains(selected) {
            self.selected = nil
        }
    }

    /// The sidebar moved to `section`, whose grid is `grid`. A playlist's section
    /// starts with nothing selected: the inspector shows a selected wallpaper
    /// before the playlist, so a kept selection would hide the playlist's settings.
    public mutating func sectionChanged(to section: LibrarySection, grid: [WallpaperID]) {
        if case .playlist = section {
            selected = nil
        } else {
            gridChanged(grid)
        }
    }
}
