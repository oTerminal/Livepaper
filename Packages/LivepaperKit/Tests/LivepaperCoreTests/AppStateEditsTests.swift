import Foundation
import LivepaperTestSupport
import Testing
import LivepaperCore

struct AppStateEditsTests {
    static let first = DisplayIdentity.numbered(1)
    static let second = DisplayIdentity.numbered(2)
    static let unplugged = DisplayIdentity.numbered(3)

    /// Wallpapers 1, 2 and 3, in order.
    static let evening = Playlist(
        id: .numbered(1), name: "Evening", wallpapers: [.numbered(1), .numbered(2), .numbered(3)], interval: .seconds(600), shuffle: false
    )
    static let morning = Playlist(
        id: .numbered(2), name: "Morning", wallpapers: [.numbered(4), .numbered(5)], interval: .seconds(600), shuffle: false
    )

    static func state(_ change: (inout AppState) -> Void = { _ in }) -> AppState {
        var state = AppState()
        state.playlists = [evening, morning]
        change(&state)
        return state
    }

    static func assigning(_ assignment: Assignment, to displays: [DisplayIdentity], in state: AppState, seed: UInt64 = 1) -> AppState {
        var rng = SeededGenerator(seed: seed)
        return state.assigning(assignment, to: displays, now: Moment.launch, rng: &rng)
    }

    // MARK: What a display shows

    static let resolved: [Row<AppState, Assignment?>] = [
        Row("its own assignment", state { $0.assignments[first] = .wallpaper(.numbered(1)) }, .wallpaper(.numbered(1))),
        Row(
            "its own assignment before apply to all",
            state {
                $0.assignments[first] = .wallpaper(.numbered(1))
                $0.applyToAll = .playlist(.numbered(1))
            },
            .wallpaper(.numbered(1))
        ),
        Row("apply to all, without one of its own", state { $0.applyToAll = .playlist(.numbered(1)) }, .playlist(.numbered(1))),
        Row("nothing", state(), nil),
    ]

    @Test(arguments: resolved)
    func `a display shows its own assignment, else apply to all`(row: Row<AppState, Assignment?>) {
        #expect(row.input.assignment(for: Self.first) == row.expected)
    }

    // MARK: Set on display

    @Test func `setting a wallpaper assigns it to those displays and puts it first in the recents`() {
        let state = Self.assigning(.wallpaper(.numbered(2)), to: [Self.first, Self.second], in: Self.state())

        #expect(state.assignments == [Self.first: .wallpaper(.numbered(2)), Self.second: .wallpaper(.numbered(2))])
        #expect(state.recents == [.numbered(2)])
    }

    static let recents: [Row<[Int], [Int]>] = [
        Row("a new wallpaper goes first", [1, 2, 3], [3, 2, 1]),
        Row("a wallpaper set again moves to the front, and is there once", [1, 2, 3, 1], [1, 3, 2]),
        Row("the same wallpaper twice is there once", [4, 4], [4]),
        Row("the recents keep 8, and the oldest leaves", Array(1...10), Array((3...10).reversed())),
    ]

    @Test(arguments: recents)
    func `the recents are the last 8 wallpapers set, newest first`(row: Row<[Int], [Int]>) {
        let state = row.input.reduce(Self.state()) { state, number in
            Self.assigning(.wallpaper(.numbered(number)), to: [Self.first], in: state)
        }

        #expect(state.recents == row.expected.map(WallpaperID.numbered))
    }

    @Test func `setting a playlist starts its rotation on each display at its first wallpaper`() {
        let state = Self.assigning(.playlist(.numbered(1)), to: [Self.first, Self.second], in: Self.state())

        let started = RotationState(current: .numbered(1), position: 0, lastRotation: Moment.launch)
        #expect(state.assignments == [Self.first: .playlist(.numbered(1)), Self.second: .playlist(.numbered(1))])
        #expect(state.rotation == [Self.first: started, Self.second: started])
        #expect(state.recents.isEmpty)
    }

    @Test func `setting a playlist again starts it again`() {
        let showingThree = Self.state {
            $0.assignments[Self.first] = .playlist(.numbered(1))
            $0.rotation[Self.first] = RotationState(current: .numbered(3), position: 2, lastRotation: Moment.after(-60))
        }

        let state = Self.assigning(.playlist(.numbered(1)), to: [Self.first], in: showingThree)

        #expect(state.rotation[Self.first] == RotationState(current: .numbered(1), position: 0, lastRotation: Moment.launch))
    }

    @Test func `setting a wallpaper on a display showing a playlist ends its rotation`() {
        let showingPlaylist = Self.assigning(.playlist(.numbered(1)), to: [Self.first, Self.second], in: Self.state())

        let state = Self.assigning(.wallpaper(.numbered(9)), to: [Self.first], in: showingPlaylist)

        #expect(state.rotation.keys.sorted { $0.description < $1.description } == [Self.second])
    }

    @Test func `setting on no displays changes nothing`() {
        #expect(Self.assigning(.wallpaper(.numbered(1)), to: [], in: Self.state()) == Self.state())
    }

    // MARK: All Displays

    @Test func `setting on All Displays sets apply to all and clears every display's own assignment, plugged in or not`() {
        let before = Self.state {
            $0.assignments = [Self.first: .wallpaper(.numbered(1)), Self.unplugged: .playlist(.numbered(1))]
            $0.rotation[Self.unplugged] = RotationState(current: .numbered(2), position: 1)
        }
        var rng = SeededGenerator(seed: 1)

        let state = before.assigningToAll(.wallpaper(.numbered(4)), connected: [Self.first, Self.second], now: Moment.launch, rng: &rng)

        #expect(state.applyToAll == .wallpaper(.numbered(4)))
        #expect(state.assignments.isEmpty)
        #expect(state.rotation.isEmpty)
        #expect(state.recents == [.numbered(4)])
        #expect([Self.first, Self.second, Self.unplugged].allSatisfy { state.assignment(for: $0) == .wallpaper(.numbered(4)) })
    }

    @Test func `setting a playlist on All Displays starts it on each connected display`() {
        var rng = SeededGenerator(seed: 1)
        let connected = [Self.first, Self.second]

        let state = Self.state().assigningToAll(.playlist(.numbered(2)), connected: connected, now: Moment.launch, rng: &rng)

        let started = RotationState(current: .numbered(4), position: 0, lastRotation: Moment.launch)
        #expect(state.applyToAll == .playlist(.numbered(2)))
        #expect(state.rotation == [Self.first: started, Self.second: started])
        #expect(state.recents.isEmpty)
    }

    // MARK: Unassign and pause

    @Test func `unassigning a display leaves it to apply to all, and ends its rotation`() {
        let before = Self.state {
            $0.applyToAll = .wallpaper(.numbered(5))
            $0.assignments = [Self.first: .playlist(.numbered(1)), Self.second: .wallpaper(.numbered(2))]
            $0.rotation[Self.first] = RotationState(current: .numbered(1), position: 0)
        }

        let state = before.unassigning(Self.first)

        #expect(state.assignment(for: Self.first) == .wallpaper(.numbered(5)))
        #expect(state.assignments == [Self.second: .wallpaper(.numbered(2))])
        #expect(state.rotation.isEmpty)
    }

    @Test func `pausing and resuming one display`() {
        let paused = Self.state().settingPaused(true, for: Self.first)
        let resumed = paused.settingPaused(false, for: Self.first)

        #expect(paused.pausedDisplays == [Self.first])
        #expect(resumed.pausedDisplays.isEmpty)
    }

    // MARK: Next

    static func showingPlaylist(_ id: PlaylistID = .numbered(1), rotation: RotationState?) -> AppState {
        state {
            $0.assignments[first] = .playlist(id)
            $0.rotation[first] = rotation
        }
    }

    static func next(_ state: AppState, seed: UInt64 = 1) -> AppState {
        var rng = SeededGenerator(seed: seed)
        return state.rotating(first, .next(at: Moment.after(5)), rng: &rng)
    }

    static let nexts: [Row<AppState, RotationState?>] = [
        Row(
            "moves on to the next wallpaper and restarts the interval",
            showingPlaylist(rotation: RotationState(current: .numbered(1), position: 0, lastRotation: Moment.launch)),
            RotationState(current: .numbered(2), position: 1, lastRotation: Moment.after(5))
        ),
        Row(
            "a playlist with no rotation yet shows its first, so Next goes to the second",
            showingPlaylist(rotation: nil),
            RotationState(current: .numbered(2), position: 1, lastRotation: Moment.after(5))
        ),
        Row(
            "after the wallpaper showing was deleted, the display shows the one that followed it, so Next goes past it",
            showingPlaylist(rotation: RotationState(current: nil, position: 1, lastRotation: Moment.launch)),
            RotationState(current: .numbered(3), position: 2, lastRotation: Moment.after(5))
        ),
        Row("a display showing a wallpaper has nothing to move on", state { $0.assignments[first] = .wallpaper(.numbered(1)) }, nil),
        Row("a display showing nothing has nothing to move on", state(), nil),
    ]

    @Test(arguments: nexts)
    func `pressing Next moves on the playlist a display shows`(row: Row<AppState, RotationState?>) {
        #expect(Self.next(row.input).rotation[Self.first] == row.expected)
    }

    @Test func `pressing Next on a display showing apply to all's playlist`() {
        let state = Self.next(Self.state { $0.applyToAll = .playlist(.numbered(2)) })

        #expect(state.rotation[Self.first]?.current == .numbered(5))
    }

    @Test(arguments: [UInt64](0..<20))
    func `pressing Next on a shuffled playlist with no rotation yet never stays on the first`(seed: UInt64) {
        var shuffled = Self.evening
        shuffled.shuffle = true
        let state = Self.state {
            $0.playlists = [shuffled]
            $0.assignments[Self.first] = .playlist(shuffled.id)
        }

        let current = Self.next(state, seed: seed).rotation[Self.first]?.current

        #expect(current != nil && current != .numbered(1))
    }

    // MARK: Previous

    @Test func `stepping back puts the rotation back on a wallpaper, keeping the shuffled pass`() {
        let before = Self.showingPlaylist(
            rotation: RotationState(current: .numbered(3), position: 2, upcoming: [.numbered(1)], lastRotation: Moment.launch)
        )

        let state = before.steppingBack(Self.first, to: .numbered(2))

        #expect(state.rotation[Self.first] == RotationState(
            current: .numbered(2), position: 1, upcoming: [.numbered(1)], lastRotation: Moment.launch
        ))
    }

    @Test func `stepping back to a wallpaper the playlist no longer has changes nothing`() {
        let before = Self.showingPlaylist(rotation: RotationState(current: .numbered(3), position: 2))

        #expect(before.steppingBack(Self.first, to: .numbered(9)) == before)
    }

    // MARK: Playlists

    @Test func `a new playlist goes last, in the user's order`() {
        let new = Playlist(id: .numbered(3), name: "Night", wallpapers: [], interval: Playlist.defaultInterval, shuffle: false)

        let state = Self.state().creatingPlaylist(new)

        #expect(state.playlists.map(\.id) == [.numbered(1), .numbered(2), .numbered(3)])
        #expect(state.creatingPlaylist(new) == state)
    }

    @Test func `deleting a playlist removes the assignments naming it and their rotations`() {
        let before = Self.state {
            $0.applyToAll = .playlist(.numbered(1))
            $0.assignments = [Self.first: .playlist(.numbered(1)), Self.second: .playlist(.numbered(2))]
            $0.rotation = [Self.first: RotationState(current: .numbered(1)), Self.second: RotationState(current: .numbered(4))]
        }

        let state = before.deletingPlaylist(.numbered(1))

        #expect(state.playlists.map(\.id) == [.numbered(2)])
        #expect(state.applyToAll == nil)
        #expect(state.assignments == [Self.second: .playlist(.numbered(2))])
        #expect(state.rotation == [Self.second: RotationState(current: .numbered(4))])
    }

    static let renames: [Row<String, String?>] = [
        Row("a new name", "Late evening", "Late evening"),
        Row("spaces around the name are dropped", "  Night \n", "Night"),
        Row("an empty name is refused", "", nil),
        Row("a name of spaces is refused", "   ", nil),
    ]

    @Test(arguments: renames)
    func `renames a playlist`(row: Row<String, String?>) throws {
        if let expected = row.expected {
            #expect(try Self.state().renamingPlaylist(.numbered(1), to: row.input)[playlist: .numbered(1)]?.name == expected)
        } else {
            #expect(throws: LibraryError.emptyName) { try Self.state().renamingPlaylist(.numbered(1), to: row.input) }
        }
    }

    @Test func `sets a playlist's interval and shuffle`() {
        let state = Self.state().settingPlaylist(.numbered(1), interval: .seconds(90)).settingPlaylist(.numbered(1), shuffle: true)

        #expect(state[playlist: .numbered(1)]?.interval == .seconds(90))
        #expect(state[playlist: .numbered(1)]?.shuffle == true)
        #expect(state[playlist: .numbered(2)] == Self.morning)
    }

    @Test func `adds a wallpaper to a playlist once, at the end, and removes it`() {
        let added = Self.state().adding(.numbered(5), toPlaylist: .numbered(1)).adding(.numbered(5), toPlaylist: .numbered(1))
        let removed = added.removing(.numbered(2), fromPlaylist: .numbered(1))

        #expect(added[playlist: .numbered(1)]?.wallpapers == [1, 2, 3, 5].map(WallpaperID.numbered))
        #expect(removed[playlist: .numbered(1)]?.wallpapers == [1, 3, 5].map(WallpaperID.numbered))
        #expect(removed[playlist: .numbered(2)] == Self.morning)
    }

    @Test func `edits to a playlist that is not there change nothing`() throws {
        let state = Self.state()
        let missing = PlaylistID.numbered(9)

        #expect(state.deletingPlaylist(missing) == state)
        #expect(try state.renamingPlaylist(missing, to: "Night") == state)
        #expect(state.settingPlaylist(missing, shuffle: true) == state)
        #expect(state.adding(.numbered(1), toPlaylist: missing) == state)
    }
}

// Set on Display's checkmark.
extension AppStateEditsTests {
    static let checked: [Row<AppState, Bool>] = [
        Row("its own assignment is this wallpaper", state { $0.assignments[first] = .wallpaper(.numbered(1)) }, true),
        Row("apply to all's is, and it has none of its own", state { $0.applyToAll = .wallpaper(.numbered(1)) }, true),
        Row("another wallpaper", state { $0.assignments[first] = .wallpaper(.numbered(2)) }, false),
        Row(
            "its own assignment goes before apply to all's",
            state {
                $0.assignments[first] = .wallpaper(.numbered(2))
                $0.applyToAll = .wallpaper(.numbered(1))
            },
            false
        ),
        Row("a playlist that holds it", state { $0.assignments[first] = .playlist(.numbered(1)) }, false),
        Row("nothing", state(), false),
    ]

    @Test(arguments: checked)
    func `a display that shows this wallpaper is checked in Set on Display`(row: Row<AppState, Bool>) {
        #expect(row.input.shows(.wallpaper(.numbered(1)), on: Self.first) == row.expected)
    }
}

// A new playlist's name, from the sidebar's New Playlist or a wallpaper's menu.
extension AppStateEditsTests {
    static let newNames: [Row<String, String?>] = [
        Row("a name", "Night", "Night"),
        Row("spaces around the name are dropped", "  Night \n", "Night"),
        Row("an empty name is refused", "", nil),
        Row("a name of spaces is refused", "   ", nil),
    ]

    @Test(arguments: newNames)
    func `a new playlist is named as a rename names it, and rotates every 30 minutes in order`(row: Row<String, String?>) throws {
        let make = { try Self.state().creatingPlaylist(.numbered(3), named: row.input, with: [.numbered(4)]) }

        if let expected = row.expected {
            #expect(try make().playlists.last == Playlist(
                id: .numbered(3), name: expected, wallpapers: [.numbered(4)], interval: .seconds(30 * 60), shuffle: false
            ))
        } else {
            #expect(throws: LibraryError.emptyName) { try make() }
        }
    }
}
