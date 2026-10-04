import Foundation
import LivepaperTestSupport
import Testing
import LivepaperCore

struct RotationHistoryTests {
    static func playlist(_ numbers: [Int]) -> Playlist {
        Playlist(id: .numbered(1), name: "Evening", wallpapers: numbers.map(WallpaperID.numbered), interval: .seconds(600), shuffle: true)
    }

    struct Walk: Sendable {
        /// The wallpapers left, in the order Next left them.
        var left: [Int]
        var playlist: [Int]
        var current: Int?
    }

    static let rows: [Row<Walk, Int?>] = [
        Row("the wallpaper shown before this one", Walk(left: [3, 1], playlist: [1, 2, 3], current: 2), 1),
        Row("one that has left the playlist is passed over", Walk(left: [3, 1], playlist: [2, 3], current: 2), 3),
        Row("the one showing is passed over", Walk(left: [1, 2], playlist: [1, 2, 3], current: 2), 1),
        Row("with no history, the one before in the playlist's order", Walk(left: [], playlist: [1, 2, 3], current: 2), 1),
        Row("with no history, before the first is the last", Walk(left: [], playlist: [1, 2, 3], current: 1), 3),
        Row("with no history and nothing showing, the last", Walk(left: [], playlist: [1, 2, 3], current: nil), 3),
        Row("a playlist of one has no previous", Walk(left: [2], playlist: [1], current: 1), nil),
        Row("an empty playlist has no previous", Walk(left: [2], playlist: [], current: nil), nil),
    ]

    @Test(arguments: rows)
    func `stepping back goes through what this session showed`(row: Row<Walk, Int?>) {
        var history = RotationHistory()
        for number in row.input.left {
            history.leaving(.numbered(number))
        }

        let previous = history.previous(in: Self.playlist(row.input.playlist), current: row.input.current.map(WallpaperID.numbered))

        #expect(previous == row.expected.map(WallpaperID.numbered))
    }

    @Test func `pressing Previous again steps further back`() {
        var history = RotationHistory()
        let playlist = Self.playlist([1, 2, 3, 4])
        for number in [4, 1, 3] {
            history.leaving(.numbered(number))
        }

        let steps = [
            history.previous(in: playlist, current: .numbered(2)),
            history.previous(in: playlist, current: .numbered(3)),
            history.previous(in: playlist, current: .numbered(1)),
            history.previous(in: playlist, current: .numbered(4)),
        ]

        #expect(steps == [3, 1, 4, 3].map(WallpaperID.numbered))
    }
}

/// Next and Previous as the popover's transport presses them, over the app state, with each display's
/// history kept beside it for the session.
struct RotationHistoriesTests {
    static let first = DisplayIdentity.numbered(1)
    static let second = DisplayIdentity.numbered(2)

    /// Wallpapers 1 to 4, in that order, not shuffled.
    static let evening = Playlist(
        id: .numbered(1), name: "Evening", wallpapers: (1...4).map(WallpaperID.numbered), interval: .seconds(600), shuffle: false
    )

    static func library() throws -> Library {
        try Library.of(contentsOf: (1...5).map { Wallpaper.numbered($0) })
    }

    /// Both displays on Evening, started at its first wallpaper.
    static var state: AppState {
        var state = AppState()
        state.playlists = [evening]
        var rng = SeededGenerator(seed: 1)
        return state.assigning(.playlist(evening.id), to: [first, second], now: Moment.launch, rng: &rng)
    }

    enum Press: Sendable {
        case next(DisplayIdentity = first)
        case previous(DisplayIdentity = first)
        /// Set on Display: the display now shows something else.
        case set(Assignment, on: DisplayIdentity = first)
    }

    /// Plays the presses as the model does: each one's state is committed, and the histories hear of every change.
    static func play(_ presses: [Press]) throws -> AppState {
        let library = try library()
        var histories = RotationHistories()
        var state = state
        var rng = SeededGenerator(seed: 1)
        for press in presses {
            let next = switch press {
            case .next(let display): histories.next(on: display, in: state, library: library, now: Moment.after(60), rng: &rng)
            case .previous(let display): histories.previous(on: display, in: state, library: library)
            case .set(let assignment, let display): state.assigning(assignment, to: [display], now: Moment.after(60), rng: &rng)
            }
            histories.forget(changedFrom: state, to: next)
            state = next
        }
        return state
    }

    static let walks: [Row<[Press], Int?>] = [
        Row("Next moves on", [.next()], 2),
        Row("Next twice and Previous once: back to the one before", [.next(), .next(), .previous()], 2),
        Row("Previous again steps further back", [.next(), .next(), .previous(), .previous()], 1),
        Row("with nothing seen yet, Previous goes back through the playlist's order", [.previous()], 4),
        Row(
            "a display that was set to something else starts again",
            [.next(), .next(), .set(.wallpaper(.numbered(5))), .set(.playlist(.numbered(1))), .previous()],
            4
        ),
        Row("each display has its own", [.next(), .next(), .next(second), .previous(second)], 3),
        Row("a display showing a wallpaper has no Next", [.set(.wallpaper(.numbered(5))), .next()], 5),
        Row("nor a Previous", [.set(.wallpaper(.numbered(5))), .previous()], 5),
    ]

    @Test(arguments: walks)
    func `pressing Next and Previous walks the playlist and what this session showed`(row: Row<[Press], Int?>) throws {
        let state = try Self.play(row.input)

        #expect(state.wallpaper(shownOn: Self.first, in: try Self.library())?.id == row.expected.map(WallpaperID.numbered))
    }

    @Test func `the other display steps back through its own`() throws {
        let state = try Self.play([.next(), .next(), .next(Self.second), .previous(Self.second)])

        #expect(state.wallpaper(shownOn: Self.second, in: try Self.library())?.id == .numbered(1))
    }

    @Test func `pressing Next or Previous on a display showing a wallpaper changes nothing`() throws {
        let library = try Self.library()
        var histories = RotationHistories()
        var rng = SeededGenerator(seed: 1)
        let state = Self.state.assigning(.wallpaper(.numbered(5)), to: [Self.first], now: Moment.launch, rng: &rng)

        #expect(histories.next(on: Self.first, in: state, library: library, now: Moment.after(60), rng: &rng) == state)
        #expect(histories.previous(on: Self.first, in: state, library: library) == state)
    }
}
