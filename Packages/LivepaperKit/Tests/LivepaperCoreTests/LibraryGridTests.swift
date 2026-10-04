import Foundation
import Testing
import LivepaperCore

struct LibraryGridTests {
    static let first = DisplayIdentity.numbered(1)
    static let second = DisplayIdentity.numbered(2)
    static let third = DisplayIdentity.numbered(3)

    /// Imported 1 to 5 in that order; 2 and 4 are favourites.
    static func library() throws -> Library {
        try Library.of(
            .numbered(1, name: "Ocean at Dusk"),
            .numbered(2, name: "Café Lights", isFavourite: true),
            .numbered(3, name: "Aurora"),
            .numbered(4, name: "ocean, stormy", isFavourite: true),
            .numbered(5, name: "Forest")
        )
    }

    /// "Evening" is 5, 1, 4 and 9, which the library has lost; "Empty" has none.
    /// The first display shows Evening, the second wallpaper 3, the third nothing.
    static var state: AppState {
        let evening = [5, 1, 4, 9].map(WallpaperID.numbered)
        var state = AppState()
        state.playlists = [
            Playlist(id: .numbered(1), name: "Evening", wallpapers: evening, interval: .seconds(600), shuffle: false),
            Playlist(id: .numbered(2), name: "Empty", wallpapers: [], interval: .seconds(600), shuffle: false),
        ]
        state.assignments = [first: .playlist(.numbered(1)), second: .wallpaper(.numbered(3))]
        return state
    }

    // MARK: Sidebar

    @Test func `the sidebar counts the library, the favourites and each playlist's wallpapers still in the library`() throws {
        let counts = sidebarCounts(library: try Self.library(), state: Self.state)

        #expect(counts == SidebarCounts(all: 5, favourites: 2, playlists: [.numbered(1): 3, .numbered(2): 0]))
    }

    // MARK: The sidebar's section

    static let fallbacks: [Row<LibrarySection, LibrarySection>] = [
        Row("All stays", .all, .all),
        Row("Favourites stays", .favourites, .favourites),
        Row("a playlist that is there stays", .playlist(.numbered(2)), .playlist(.numbered(2))),
        Row("a playlist that has gone falls back to All", .playlist(.numbered(7)), .all),
        Row("a connected display stays", .nowPlaying(second), .nowPlaying(second)),
        Row("a display that has gone falls back to All", .nowPlaying(third), .all),
    ]

    @Test(arguments: fallbacks)
    func `a section whose display or playlist has gone falls back to All`(row: Row<LibrarySection, LibrarySection>) {
        #expect(row.input.resolved(displays: [Self.first, Self.second], playlists: Self.state.playlists) == row.expected)
    }

    static let newPlaylists: [Row<[Int], LibrarySection>] = [
        Row("an empty playlist is where the user goes next, to fill it", [], .playlist(.numbered(3))),
        Row("one made from a wallpaper's menu, with it in, leaves the user where they were", [2], .favourites),
    ]

    @Test(arguments: newPlaylists)
    func `the sidebar goes to a new playlist only when it is empty`(row: Row<[Int], LibrarySection>) {
        let playlist = Playlist(
            id: .numbered(3), name: "Night", wallpapers: row.input.map(WallpaperID.numbered), interval: .seconds(600), shuffle: false
        )

        #expect(LibrarySection.favourites.afterCreating(playlist) == row.expected)
    }

    // MARK: Grid

    struct Query: Sendable {
        var section: LibrarySection
        var search = ""
        var sort = Library.SortOrder.newestFirst
    }

    static let grids: [Row<Query, [Int]>] = [
        Row("all, newest first", Query(section: .all), [5, 4, 3, 2, 1]),
        Row("all, oldest first", Query(section: .all, sort: .oldestFirst), [1, 2, 3, 4, 5]),
        Row("all, by name", Query(section: .all, sort: .name), [3, 2, 5, 1, 4]),
        Row("all, searched", Query(section: .all, search: "ocean"), [4, 1]),
        Row("favourites", Query(section: .favourites), [4, 2]),
        Row("favourites, searched", Query(section: .favourites, search: "cafe"), [2]),
        Row("a playlist keeps the user's order, whatever the sort", Query(section: .playlist(.numbered(1)), sort: .name), [5, 1, 4]),
        Row("a playlist, searched", Query(section: .playlist(.numbered(1)), search: "OCEAN"), [1, 4]),
        Row("an empty playlist", Query(section: .playlist(.numbered(2))), []),
        Row("a playlist that is not there", Query(section: .playlist(.numbered(7))), []),
        Row("a display showing a playlist shows its wallpapers", Query(section: .nowPlaying(first), sort: .oldestFirst), [5, 1, 4]),
        Row("a display showing a wallpaper", Query(section: .nowPlaying(second)), [3]),
        Row("a display showing a wallpaper that does not match", Query(section: .nowPlaying(second), search: "forest"), []),
        Row("a display showing nothing", Query(section: .nowPlaying(third)), []),
        Row("no match", Query(section: .all, search: "desert"), []),
    ]

    @Test(arguments: grids)
    func `the grid is the section's wallpapers, searched and sorted`(row: Row<Query, [Int]>) throws {
        var state = Self.state
        state.sortOrder = row.input.sort

        let grid = libraryGrid(library: try Self.library(), state: state, section: row.input.section, search: row.input.search)

        #expect(grid.map(\.id) == row.expected.map(WallpaperID.numbered))
    }

    // MARK: Empty states

    struct Emptiness: Sendable {
        /// Which of the five wallpapers the library still has.
        var library = [1, 2, 3, 4, 5]
        var section: LibrarySection
        var search = ""
    }

    static let emptiness: [Row<Emptiness, EmptyGrid?>] = [
        Row("wallpapers to show: no empty state", Emptiness(section: .all), nil),
        Row("a search with matches: no empty state", Emptiness(section: .favourites, search: "cafe"), nil),
        Row("an empty library", Emptiness(library: [], section: .all), .noWallpapers),
        Row("an empty library, in any section: Import is the way on", Emptiness(library: [], section: .favourites), .noWallpapers),
        Row("an empty library, on a display", Emptiness(library: [], section: .nowPlaying(third)), .noWallpapers),
        Row("an empty library, searched", Emptiness(library: [], section: .all, search: "ocean"), .noWallpapers),
        Row("no favourites", Emptiness(library: [1, 3, 5], section: .favourites), .noFavourites),
        Row(
            "no favourites and a search: clearing the search would not help",
            Emptiness(library: [1, 3, 5], section: .favourites, search: "ocean"),
            .noFavourites
        ),
        Row("an empty playlist", Emptiness(section: .playlist(.numbered(2))), .emptyPlaylist(.numbered(2))),
        Row(
            "a playlist whose wallpapers the library has lost",
            Emptiness(library: [2, 3], section: .playlist(.numbered(1))),
            .emptyPlaylist(.numbered(1))
        ),
        Row("a display showing nothing", Emptiness(section: .nowPlaying(third)), .nothingOnDisplay(third)),
        Row(
            "a display whose wallpaper the library has lost",
            Emptiness(library: [1, 2, 4, 5], section: .nowPlaying(second)),
            .nothingOnDisplay(second)
        ),
        Row("nothing matches the search", Emptiness(section: .all, search: "desert"), .noResults(search: "desert")),
        Row(
            "the search as typed, without the spaces around it",
            Emptiness(section: .all, search: "  desert "),
            .noResults(search: "desert")
        ),
        Row(
            "a playlist searched, nothing matching",
            Emptiness(section: .playlist(.numbered(1)), search: "aurora"),
            .noResults(search: "aurora")
        ),
        Row(
            "a display searched, nothing matching",
            Emptiness(section: .nowPlaying(second), search: "forest"),
            .noResults(search: "forest")
        ),
    ]

    @Test(arguments: emptiness)
    func `an empty grid says why`(row: Row<Emptiness, EmptyGrid?>) throws {
        let all = try Self.library()
        let library = try Library.of(contentsOf: all.wallpapers.filter { wallpaper in
            row.input.library.map(WallpaperID.numbered).contains(wallpaper.id)
        })

        let empty = emptyGrid(library: library, state: Self.state, section: row.input.section, search: row.input.search)

        #expect(empty == row.expected)
    }

    static let sortable: [Row<LibrarySection, Bool>] = [
        Row("all", .all, true),
        Row("favourites", .favourites, true),
        Row("a playlist keeps the user's order", .playlist(.numbered(1)), false),
        Row("a display shows its wallpaper, or its playlist in the user's order", .nowPlaying(first), false),
    ]

    @Test(arguments: sortable)
    func `only the library's own sections follow the sort order`(row: Row<LibrarySection, Bool>) {
        #expect(row.input.followsSortOrder == row.expected)
    }

    // MARK: Selection

    /// Seven tiles, three to a row:
    ///
    ///     1 2 3
    ///     4 5 6
    ///     7
    static let tiles = (1...7).map(WallpaperID.numbered)

    struct Moves: Sendable {
        var from: Int?
        var moves: [GridSelection.Move]
    }

    static let moves: [Row<Moves, Int?>] = [
        Row("right", Moves(from: 1, moves: [.right]), 2),
        Row("left", Moves(from: 2, moves: [.left]), 1),
        Row("right at the end of a row goes on to the next row", Moves(from: 3, moves: [.right]), 4),
        Row("left at the start of a row goes back to the row before", Moves(from: 4, moves: [.left]), 3),
        Row("left from the first stays", Moves(from: 1, moves: [.left]), 1),
        Row("right from the last stays", Moves(from: 7, moves: [.right]), 7),
        Row("down a row", Moves(from: 2, moves: [.down]), 5),
        Row("up a row", Moves(from: 5, moves: [.up]), 2),
        Row("up from the top row stays", Moves(from: 2, moves: [.up]), 2),
        Row("down onto a short last row, with no tile below, goes to the last", Moves(from: 5, moves: [.down]), 7),
        Row("down from the last row stays", Moves(from: 7, moves: [.down]), 7),
        Row("first and last", Moves(from: 5, moves: [.first, .right, .last]), 7),
        Row("from nothing, an arrow selects the first", Moves(from: nil, moves: [.down]), 1),
        Row("from nothing, the last selects the last", Moves(from: nil, moves: [.last]), 7),
        Row("a selection that has left the grid starts again at the first", Moves(from: 9, moves: [.right]), 1),
    ]

    @Test(arguments: moves)
    func `arrows move the selection over the grid`(row: Row<Moves, Int?>) {
        var selection = GridSelection(selected: row.input.from.map(WallpaperID.numbered))

        for move in row.input.moves {
            selection.move(move, in: Self.tiles, columns: 3)
        }

        #expect(selection.selected == row.expected.map(WallpaperID.numbered))
    }

    @Test func `an arrow over an empty grid selects nothing`() {
        var selection = GridSelection(selected: .numbered(1))

        selection.move(.right, in: [], columns: 3)

        #expect(selection.selected == nil)
    }

    @Test func `a click selects one tile`() {
        var selection = GridSelection()

        selection.click(.numbered(4))
        selection.click(.numbered(2))

        #expect(selection.selected == .numbered(2))
    }

    struct Delete: Sendable {
        var selected: Int?
        var deleted: Int
        var grid: [Int]
    }

    static let deletes: [Row<Delete, Int?>] = [
        Row("the one that followed it", Delete(selected: 2, deleted: 2, grid: [1, 2, 3]), 3),
        Row("the last goes to the one before", Delete(selected: 3, deleted: 3, grid: [1, 2, 3]), 2),
        Row("the only one leaves nothing selected", Delete(selected: 1, deleted: 1, grid: [1]), nil),
        Row("another tile's delete keeps the selection", Delete(selected: 1, deleted: 3, grid: [1, 2, 3]), 1),
    ]

    @Test(arguments: deletes)
    func `after a delete, the selection moves on`(row: Row<Delete, Int?>) {
        var selection = GridSelection(selected: row.input.selected.map(WallpaperID.numbered))

        selection.deleted(.numbered(row.input.deleted), from: row.input.grid.map(WallpaperID.numbered))

        #expect(selection.selected == row.expected.map(WallpaperID.numbered))
    }

    @Test func `a new grid keeps the selection when it is still there, and clears it when it is not`() {
        var selection = GridSelection(selected: .numbered(2))

        selection.gridChanged([.numbered(3), .numbered(2)])
        let kept = selection.selected
        selection.gridChanged([.numbered(3)])

        #expect(kept == .numbered(2))
        #expect(selection.selected == nil)
    }

    static let sections: [Row<LibrarySection, Int?>] = [
        Row("a playlist starts with nothing selected, so the inspector shows the playlist", .playlist(.numbered(1)), nil),
        Row("favourites keep the selection their grid shows", .favourites, 2),
        Row("all wallpapers keep it too", .all, 2),
        Row("a display's section keeps it while its grid shows it", .nowPlaying(.numbered(1)), 2),
    ]

    @Test(arguments: sections)
    func `choosing a section in the sidebar`(row: Row<LibrarySection, Int?>) {
        var selection = GridSelection(selected: .numbered(2))

        selection.sectionChanged(to: row.input, grid: [.numbered(1), .numbered(2)])

        #expect(selection.selected == row.expected.map(WallpaperID.numbered))
    }
}
