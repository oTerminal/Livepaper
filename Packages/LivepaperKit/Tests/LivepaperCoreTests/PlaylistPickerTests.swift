import Foundation
import LivepaperTestSupport
import Testing
import LivepaperCore

/// The popover's playlist picker, one display at a time: a playlist starts on
/// the display, and No Playlist keeps what the display shows now.
struct PlaylistPickerTests {
    static let first = AppStateEditsTests.first
    static let second = AppStateEditsTests.second

    static func library() throws -> Library {
        try Library.of(.numbered(1), .numbered(2), .numbered(3), .numbered(4), .numbered(5))
    }

    static func choosing(_ id: PlaylistID?, for display: DisplayIdentity = first, in state: AppState) throws -> AppState {
        var rng = SeededGenerator(seed: 1)
        return state.choosingPlaylist(id, for: display, in: try library(), now: Moment.launch, rng: &rng)
    }

    /// The first display on the second wallpaper of Evening, the second on Morning.
    static let onPlaylists = AppStateEditsTests.state {
        $0.assignments = [first: .playlist(.numbered(1)), second: .playlist(.numbered(2))]
        $0.rotation = [
            first: RotationState(current: .numbered(2), position: 1, lastRotation: Moment.after(-60)),
            second: RotationState(current: .numbered(4), position: 0, lastRotation: Moment.after(-60)),
        ]
        $0.recents = [.numbered(5)]
    }

    @Test func `a playlist starts on the display at its first wallpaper`() throws {
        let state = try Self.choosing(.numbered(1), in: AppStateEditsTests.state())

        #expect(state.assignments == [Self.first: .playlist(.numbered(1))])
        #expect(state.rotation[Self.first] == RotationState(current: .numbered(1), position: 0, lastRotation: Moment.launch))
    }

    @Test func `the playlist a display already shows carries on where it is`() throws {
        #expect(try Self.choosing(.numbered(1), in: Self.onPlaylists) == Self.onPlaylists)
    }

    @Test func `another playlist replaces the one the display shows`() throws {
        let state = try Self.choosing(.numbered(2), in: Self.onPlaylists)

        #expect(state.assignments[Self.first] == .playlist(.numbered(2)))
        #expect(state.rotation[Self.first] == RotationState(current: .numbered(4), position: 0, lastRotation: Moment.launch))
    }

    @Test func `choosing No Playlist keeps the wallpaper the display shows, as its own assignment`() throws {
        let state = try Self.choosing(nil, in: Self.onPlaylists)

        #expect(state.assignments == [Self.first: .wallpaper(.numbered(2)), Self.second: .playlist(.numbered(2))])
        #expect(state.rotation.keys.sorted { $0.description < $1.description } == [Self.second])
        // The user chose no wallpaper, so the recents are left alone.
        #expect(state.recents == [.numbered(5)])
    }

    @Test func `choosing No Playlist on a display showing apply to all's playlist gives it its own wallpaper, and no other`() throws {
        let before = AppStateEditsTests.state {
            $0.applyToAll = .playlist(.numbered(1))
            $0.rotation = [
                Self.first: RotationState(current: .numbered(3), position: 2),
                Self.second: RotationState(current: .numbered(1), position: 0),
            ]
        }

        let state = try Self.choosing(nil, in: before)

        #expect(state.assignments == [Self.first: .wallpaper(.numbered(3))])
        #expect(state.applyToAll == .playlist(.numbered(1)))
        #expect(state.rotation == [Self.second: RotationState(current: .numbered(1), position: 0)])
    }

    static let unchanged: [Row<AppState, Void>] = [
        Row("a display showing a wallpaper", AppStateEditsTests.state { $0.assignments[first] = .wallpaper(.numbered(1)) }, ()),
        Row("a display showing nothing", AppStateEditsTests.state(), ()),
    ]

    @Test(arguments: unchanged)
    func `choosing No Playlist changes nothing on a display showing no playlist`(row: Row<AppState, Void>) throws {
        #expect(try Self.choosing(nil, in: row.input) == row.input)
    }

    @Test func `choosing No Playlist on a playlist with nothing to show takes the display's own assignment away`() throws {
        let empty = Playlist(id: .numbered(3), name: "Empty", wallpapers: [], interval: Playlist.defaultInterval, shuffle: false)
        let before = AppStateEditsTests.state {
            $0.playlists.append(empty)
            $0.assignments[Self.first] = .playlist(empty.id)
        }

        let state = try Self.choosing(nil, in: before)

        #expect(state.assignments.isEmpty)
    }

    @Test func `a playlist that is not there changes nothing`() throws {
        #expect(try Self.choosing(.numbered(9), in: Self.onPlaylists) == Self.onPlaylists)
    }
}
