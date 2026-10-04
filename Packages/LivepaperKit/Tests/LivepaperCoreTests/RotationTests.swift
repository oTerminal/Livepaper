import Foundation
import LivepaperTestSupport
import Testing
import LivepaperCore

struct RotationTests {
    static let one = WallpaperID.numbered(1)
    static let two = WallpaperID.numbered(2)
    static let three = WallpaperID.numbered(3)

    static func playlist(_ wallpapers: [WallpaperID], shuffle: Bool = false) -> Playlist {
        Playlist(id: .numbered(1), name: "Evening", wallpapers: wallpapers, interval: .seconds(600), shuffle: shuffle)
    }

    /// Rotates on wake `count` times and returns what was shown.
    static func rotate(
        _ playlist: Playlist, from state: RotationState = RotationState(), count: Int, seed: UInt64 = 1
    ) -> [WallpaperID?] {
        var rng = SeededGenerator(seed: seed)
        var state = state
        return (0..<count).map { step in
            let (next, shown) = nextRotation(playlist, state, .wake(at: Moment.after(Double(step))), rng: &rng)
            state = next
            return shown
        }
    }

    // MARK: Events

    struct Step: Sendable {
        var lastRotation: Date?
        var event: RotationEvent
    }

    /// A 10 minute playlist of [one, two, three] that is showing `one`.
    static let eventRows: [Row<Step, WallpaperID?>] = [
        Row("a tick before the interval changes nothing", Step(lastRotation: Moment.launch, event: .tick(at: Moment.after(599))), nil),
        Row("a tick at the interval rotates", Step(lastRotation: Moment.launch, event: .tick(at: Moment.after(600))), two),
        Row("a tick long after the interval rotates once", Step(lastRotation: Moment.launch, event: .tick(at: Moment.after(9000))), two),
        Row("a tick with no rotation on record rotates", Step(lastRotation: nil, event: .tick(at: Moment.launch)), two),
        Row("wake rotates without waiting for the interval", Step(lastRotation: Moment.launch, event: .wake(at: Moment.after(5))), two),
        Row("login rotates without waiting for the interval", Step(lastRotation: Moment.launch, event: .login(at: Moment.after(5))), two),
        Row("Next rotates at once", Step(lastRotation: Moment.launch, event: .next(at: Moment.after(5))), two),
        Row("Next with no rotation on record rotates", Step(lastRotation: nil, event: .next(at: Moment.launch)), two),
    ]

    @Test(arguments: eventRows)
    func `rotates on interval, wake and login`(row: Row<Step, WallpaperID?>) {
        var rng = SeededGenerator(seed: 1)
        let state = RotationState(current: Self.one, lastRotation: row.input.lastRotation)

        let (next, shown) = nextRotation(Self.playlist([Self.one, Self.two, Self.three]), state, row.input.event, rng: &rng)

        #expect(shown == row.expected)
        #expect(next.current == (row.expected ?? Self.one))
    }

    @Test func `a rotation on wake restarts the interval`() {
        var rng = SeededGenerator(seed: 1)
        let playlist = Self.playlist([Self.one, Self.two, Self.three])
        let showingOne = RotationState(current: Self.one, lastRotation: Moment.launch)

        let (afterWake, _) = nextRotation(playlist, showingOne, .wake(at: Moment.after(590)), rng: &rng)
        let (_, shown) = nextRotation(playlist, afterWake, .tick(at: Moment.after(600)), rng: &rng)

        #expect(shown == nil)
    }

    // MARK: Next

    @Test func `after Next, the interval starts again from it`() {
        var rng = SeededGenerator(seed: 1)
        let playlist = Self.playlist([Self.one, Self.two, Self.three])
        let showingOne = RotationState(current: Self.one, lastRotation: Moment.launch)

        let (afterNext, _) = nextRotation(playlist, showingOne, .next(at: Moment.after(590)), rng: &rng)
        let (_, early) = nextRotation(playlist, afterNext, .tick(at: Moment.after(600)), rng: &rng)
        let (_, onTime) = nextRotation(playlist, afterNext, .tick(at: Moment.after(1190)), rng: &rng)

        #expect(afterNext.lastRotation == Moment.after(590))
        #expect(early == nil)
        #expect(onTime == Self.three)
    }

    @Test func `on a new playlist in order, Next picks its first wallpaper`() {
        var rng = SeededGenerator(seed: 1)
        let playlist = Self.playlist([Self.two, Self.one, Self.three])

        let (state, shown) = nextRotation(playlist, RotationState(), .next(at: Moment.launch), rng: &rng)

        #expect(shown == Self.two)
        #expect(state == RotationState(current: Self.two, position: 0, lastRotation: Moment.launch))
    }

    @Test func `on a new shuffled playlist, Next picks the first of the shuffled pass`() {
        var rng = SeededGenerator(seed: 42)
        let playlist = Self.playlist((1...5).map(WallpaperID.numbered), shuffle: true)

        let (state, shown) = nextRotation(playlist, RotationState(), .next(at: Moment.launch), rng: &rng)

        // The pass pinned in `a seeded generator gives a fixed sequence`.
        #expect(shown == .numbered(2))
        #expect(state.upcoming == [3, 1, 5, 4].map(WallpaperID.numbered))
        #expect(state.lastRotation == Moment.launch)
    }

    // MARK: In order

    @Test func `in order, a playlist starts at its first wallpaper and wraps`() {
        let shown = Self.rotate(Self.playlist([Self.one, Self.two, Self.three]), count: 5)

        #expect(shown == [Self.one, Self.two, Self.three, Self.one, Self.two])
    }

    // MARK: Shuffle

    @Test(arguments: [UInt64](0..<50))
    func `shuffle visits every wallpaper before repeating`(seed: UInt64) {
        let wallpapers = (1...6).map(WallpaperID.numbered)

        let shown = Self.rotate(Self.playlist(wallpapers, shuffle: true), count: 18, seed: seed)

        for pass in stride(from: 0, to: 18, by: 6) {
            #expect(Set(shown[pass..<pass + 6]) == Set(wallpapers), "pass starting at \(pass)")
        }
    }

    @Test(arguments: [UInt64](0..<50))
    func `shuffle never repeats across the reshuffle boundary`(seed: UInt64) {
        // Two wallpapers reshuffle every other rotation, and half of all reshuffles
        // would start with the wallpaper that is showing.
        let shown = Self.rotate(Self.playlist([Self.one, Self.two], shuffle: true), count: 40, seed: seed)

        for (previous, next) in zip(shown, shown.dropFirst()) {
            #expect(previous != next)
        }
    }

    @Test func `a seeded generator gives a fixed sequence`() {
        let playlist = Self.playlist((1...5).map(WallpaperID.numbered), shuffle: true)

        let first = Self.rotate(playlist, count: 10, seed: 42)
        let again = Self.rotate(playlist, count: 10, seed: 42)
        let other = Self.rotate(playlist, count: 10, seed: 43)

        #expect(first == again)
        #expect(first != other)
        // Pinned, so a change to the shuffle shows up as a change in what users see.
        #expect(first == [2, 3, 1, 5, 4, 2, 5, 4, 3, 1].map(WallpaperID.numbered))
    }

    // MARK: Small playlists

    @Test(arguments: [false, true])
    func `a playlist of one shows its wallpaper once and then changes nothing`(shuffle: Bool) {
        let shown = Self.rotate(Self.playlist([Self.one], shuffle: shuffle), count: 4)

        #expect(shown == [Self.one, nil, nil, nil])
    }

    @Test(arguments: [false, true])
    func `an empty playlist shows nothing`(shuffle: Bool) {
        let showingOne = RotationState(current: Self.one, lastRotation: Moment.launch)

        let shown = Self.rotate(Self.playlist([], shuffle: shuffle), from: showingOne, count: 2)

        #expect(shown == [nil, nil])
    }

    // MARK: Deletion

    @Test func `in order, deleting the wallpaper that is showing moves on to the one after it`() {
        var rng = SeededGenerator(seed: 1)
        let (showingTwo, _) = nextRotation(
            Self.playlist([Self.one, Self.two, Self.three]),
            RotationState(current: Self.one, lastRotation: Moment.launch),
            .wake(at: Moment.after(1)),
            rng: &rng
        )

        let (_, shown) = nextRotation(Self.playlist([Self.one, Self.three]), showingTwo, .wake(at: Moment.after(2)), rng: &rng)

        #expect(shown == Self.three)
    }

    @Test(arguments: [false, true])
    func `a deleted wallpaper does not stay up until the interval has passed`(shuffle: Bool) {
        var rng = SeededGenerator(seed: 1)
        let showingTwo = RotationState(current: Self.two, position: 1, lastRotation: Moment.launch)

        let (next, shown) = nextRotation(
            Self.playlist([Self.one, Self.three], shuffle: shuffle), showingTwo, .tick(at: Moment.after(5)), rng: &rng
        )

        #expect(shown != nil && shown != Self.two)
        #expect(next.current == shown)
        #expect(next.lastRotation == Moment.after(5))
    }

    @Test func `in order, deleting the last wallpaper while it shows wraps to the first`() {
        let showingThree = RotationState(current: Self.three, position: 2, lastRotation: Moment.launch)

        let shown = Self.rotate(Self.playlist([Self.one, Self.two]), from: showingThree, count: 1)

        #expect(shown == [Self.one])
    }

    @Test(arguments: [UInt64](0..<20))
    func `shuffle never shows a wallpaper deleted mid-rotation, and still visits the rest`(seed: UInt64) {
        var rng = SeededGenerator(seed: seed)
        let all = (1...5).map(WallpaperID.numbered)
        let (state, first) = nextRotation(Self.playlist(all, shuffle: true), RotationState(), .wake(at: Moment.launch), rng: &rng)
        let deleted = state.upcoming[0]
        let remaining = all.filter { $0 != deleted }

        let shown = [first] + Self.rotate(Self.playlist(remaining, shuffle: true), from: state, count: 3, seed: seed)

        #expect(!shown.contains(deleted))
        #expect(Set(shown.compactMap(\.self)) == Set(remaining))
    }

    @Test func `deleting down to the wallpaper that is showing changes nothing`() {
        let showingTwo = RotationState(current: Self.two, position: 1, upcoming: [Self.three, Self.one], lastRotation: Moment.launch)

        let shown = Self.rotate(Self.playlist([Self.two], shuffle: true), from: showingTwo, count: 2)

        #expect(shown == [nil, nil])
    }

    // MARK: The inspector's interval

    static func minutes(_ count: Int) -> Duration {
        .seconds(count * 60)
    }

    static let intervalChoices: [Row<Duration, [Duration]>] = [
        Row("the default is one of the choices", Playlist.defaultInterval, [5, 15, 30, 60, 180, 1440].map(minutes)),
        Row("an interval set elsewhere joins them, in order", .seconds(45 * 60), [5, 15, 30, 45, 60, 180, 1440].map(minutes)),
        Row("longer than any", .seconds(2 * 24 * 60 * 60), [5, 15, 30, 60, 180, 1440, 2880].map(minutes)),
    ]

    @Test(arguments: intervalChoices)
    func `the interval choices are a few set ones and the playlist's own`(row: Row<Duration, [Duration]>) {
        #expect(Playlist.intervalChoices(including: row.input) == row.expected)
    }
}
