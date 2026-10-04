import Foundation
import Testing
import LivepaperCore

struct DeletionTests {
    static let first = DisplayIdentity.numbered(1)
    static let second = DisplayIdentity.numbered(2)
    static let third = DisplayIdentity.numbered(3)

    /// Wallpaper 2 is everywhere: on the first display, as apply to all, in both
    /// playlists, in the recents, showing on the third display's rotation and
    /// waiting in its shuffled pass.
    static var state: AppState {
        var state = AppState()
        state.playlists = [
            Playlist(
                id: .numbered(1), name: "Evening", wallpapers: [1, 2, 3].map(WallpaperID.numbered), interval: .seconds(600), shuffle: true
            ),
            Playlist(id: .numbered(2), name: "Morning", wallpapers: [.numbered(2)], interval: .seconds(600), shuffle: false),
        ]
        state.assignments = [first: .wallpaper(.numbered(2)), second: .wallpaper(.numbered(1)), third: .playlist(.numbered(1))]
        state.applyToAll = .wallpaper(.numbered(2))
        state.rotation = [
            third: RotationState(current: .numbered(2), position: 1, upcoming: [.numbered(3), .numbered(2)], lastRotation: Moment.launch),
        ]
        state.pausedDisplays = [first]
        state.isMuted = true
        state.recents = [.numbered(1), .numbered(2), .numbered(3)]
        return state
    }

    static func library() throws -> Library {
        try Library.of(.numbered(1), .numbered(2), .numbered(3))
    }

    // MARK: Pruning

    @Test func `a deleted wallpaper leaves the assignments, apply to all, playlists, recents and rotations`() {
        let state = Self.state.removingWallpaper(.numbered(2))

        #expect(state.assignments == [Self.second: .wallpaper(.numbered(1)), Self.third: .playlist(.numbered(1))])
        #expect(state.applyToAll == nil)
        #expect(state.playlists.map(\.wallpapers) == [[.numbered(1), .numbered(3)], []])
        #expect(state.recents == [.numbered(1), .numbered(3)])
        #expect(state.rotation == [
            Self.third: RotationState(current: nil, position: 1, upcoming: [.numbered(3)], lastRotation: Moment.launch),
        ])
        #expect(state.pausedDisplays == [Self.first] && state.isMuted)
    }

    @Test func `a display that showed the deleted wallpaper falls back to apply to all`() {
        var before = Self.state
        before.applyToAll = .playlist(.numbered(1))

        let state = before.removingWallpaper(.numbered(2))

        #expect(state.assignment(for: Self.first) == .playlist(.numbered(1)))
    }

    @Test func `deleting a wallpaper nothing names changes nothing`() {
        #expect(Self.state.removingWallpaper(.numbered(9)) == Self.state)
    }

    // MARK: Delete and undo

    @Test func `a delete keeps the removal and the state from before, and prunes the state`() throws {
        let deletion = try deleteWallpaper(.numbered(2), library: Self.library(), state: Self.state)

        #expect(deletion.library.wallpapers.map(\.id) == [.numbered(1), .numbered(3)])
        #expect(deletion.state == Self.state.removingWallpaper(.numbered(2)))
        #expect(deletion.record.wallpaper == .numbered(2))
        #expect(deletion.record.priorState == Self.state)
    }

    @Test(arguments: [1, 2, 3])
    func `undo puts back the wallpaper where it was and the state from before`(number: Int) throws {
        let deletion = try deleteWallpaper(.numbered(number), library: Self.library(), state: Self.state)

        let (restored, state) = try undoDeletion(deletion.record, library: deletion.library)

        #expect(restored == (try Self.library()))
        #expect(state == Self.state)
    }

    @Test func `the undo toast names the wallpaper that was deleted`() throws {
        let library = try Library.of(.numbered(1, name: "Harbour at Dusk"))

        let deletion = try deleteWallpaper(.numbered(1), library: library, state: AppState())

        #expect(deletion.record.toastWords == "Deleted “Harbour at Dusk”")
    }

    @Test func `deleting a wallpaper that is not in the library is an error`() throws {
        #expect(throws: LibraryError.noSuchWallpaper(.numbered(9))) {
            try deleteWallpaper(.numbered(9), library: Self.library(), state: Self.state)
        }
    }
}
