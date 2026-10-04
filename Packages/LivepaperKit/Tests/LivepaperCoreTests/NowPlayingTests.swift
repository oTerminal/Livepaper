import Foundation
import Testing
import LivepaperCore

struct NowPlayingTests {
    static let first = DisplayIdentity.numbered(1)
    static let second = DisplayIdentity.numbered(2)
    static let now = Moment.after(10)

    static func library() throws -> Library {
        try Library.of(.numbered(1), .numbered(2), .numbered(3))
    }

    /// The first display shows wallpaper 1.
    static func state(_ change: (inout AppState) -> Void = { _ in }) -> AppState {
        var state = AppState()
        state.playlists = [
            Playlist(id: .numbered(1), name: "Evening", wallpapers: [.numbered(1), .numbered(2)], interval: .seconds(600), shuffle: false),
            // Only wallpaper 3 is still in the library.
            Playlist(id: .numbered(2), name: "Lost", wallpapers: [.numbered(3), .numbered(9)], interval: .seconds(600), shuffle: false),
        ]
        state.assignments[first] = .wallpaper(.numbered(1))
        change(&state)
        return state
    }

    struct Situation: Sendable {
        var state: AppState
        var conditions: SensedConditions?
        var isPausedAll = false
        /// The stopped state Quit leaves, which a relaunch reads until it makes a live one.
        var stopped = false
        var host = HostCapabilities(showsLockScreen: true)
    }

    /// The first display's card, with the render state the app would have applied.
    static func card(_ situation: Situation) throws -> NowPlaying {
        let library = try library()
        var render = RenderState.make(
            library: library,
            state: situation.state,
            connected: [first],
            conditions: situation.conditions,
            isPausedAll: situation.isPausedAll,
            previous: nil
        )
        if situation.stopped { render = render?.next { $0.isStopped = true } }
        let cards = nowPlaying(
            library: library,
            state: situation.state,
            connected: [first],
            render: render,
            isPausedAll: situation.isPausedAll,
            host: situation.host,
            now: now
        )
        return try #require(cards.first)
    }

    static func sensed(_ change: (inout SensedConditions) -> Void) -> SensedConditions {
        var conditions = SensedConditions(sensedAt: Moment.after(5))
        change(&conditions)
        return conditions
    }

    // MARK: Status

    struct Card: Equatable, Sendable {
        var status: String?
        var isPlaying: Bool
        var isUserPaused = false
    }

    static let statuses: [Row<Situation, Card>] = [
        Row("playing", Situation(state: state()), Card(status: nil, isPlaying: true)),
        Row(
            "paused by the user",
            Situation(state: state { $0.pausedDisplays = [first] }),
            Card(status: "Paused", isPlaying: false, isUserPaused: true)
        ),
        Row(
            "a covered desktop",
            Situation(state: state(), conditions: sensed { $0.coveredDisplays = [first] }),
            Card(status: "Paused: desktop covered", isPlaying: false)
        ),
        Row(
            "a covered desktop plays with its rule off",
            Situation(state: state { $0.pauseRules.whenDesktopCovered = false }, conditions: sensed { $0.coveredDisplays = [first] }),
            Card(status: nil, isPlaying: true)
        ),
        Row(
            "a display asleep",
            Situation(state: state(), conditions: sensed { $0.asleepDisplays = [first] }),
            Card(status: "Paused: display asleep", isPlaying: false)
        ),
        Row(
            "locked, on a host that cannot show the lock screen",
            Situation(state: state(), conditions: sensed { $0.locked = true }, host: HostCapabilities(showsLockScreen: false)),
            Card(status: "Paused: locked", isPlaying: false)
        ),
        Row(
            "locked, on a host that shows the lock screen, plays",
            Situation(state: state(), conditions: sensed { $0.locked = true }),
            Card(status: nil, isPlaying: true)
        ),
        Row(
            "Low Power Mode",
            Situation(state: state(), conditions: sensed { $0.lowPowerMode = true }),
            Card(status: "Paused: Low Power Mode", isPlaying: false)
        ),
        Row(
            "on battery, with its rule on",
            Situation(state: state { $0.pauseRules.onBattery = true }, conditions: sensed { $0.onBattery = true }),
            Card(status: "Paused: on battery", isPlaying: false)
        ),
        Row(
            "conditions sensed too long ago are ignored",
            Situation(state: state(), conditions: SensedConditions(sensedAt: Moment.after(-60), coveredDisplays: [first])),
            Card(status: nil, isPlaying: true)
        ),
        Row("Pause All", Situation(state: state(), isPausedAll: true), Card(status: "Paused", isPlaying: false)),
        Row(
            "Pause All over the display's own pause, which its button still shows",
            Situation(state: state { $0.pausedDisplays = [first] }, isPausedAll: true),
            Card(status: "Paused", isPlaying: false, isUserPaused: true)
        ),
        Row(
            "Pause All beats every sensed reason, as the user's pause does",
            Situation(state: state(), conditions: sensed { $0.lowPowerMode = true }, isPausedAll: true),
            Card(status: "Paused", isPlaying: false)
        ),
        Row("the stopped state Quit left", Situation(state: state(), stopped: true), Card(status: "Paused", isPlaying: false)),
        Row(
            "the user's pause beats every sensed reason",
            Situation(state: state { $0.pausedDisplays = [first] }, conditions: sensed { $0.lowPowerMode = true }),
            Card(status: "Paused", isPlaying: false, isUserPaused: true)
        ),
        Row(
            "no wallpaper has no status, and does not play",
            Situation(state: state { $0.assignments = [:] }),
            Card(status: nil, isPlaying: false)
        ),
    ]

    @Test(arguments: statuses)
    func `a card's status is the pause reason in words`(row: Row<Situation, Card>) throws {
        let card = try Self.card(row.input)

        #expect(Card(status: card.status, isPlaying: card.isPlaying, isUserPaused: card.isUserPaused) == row.expected)
    }

    static let host = HostCapabilities(showsLockScreen: true)

    @Test func `a pause the render state has yet to carry shows at once`() throws {
        let library = try Self.library()
        let paused = Self.state { $0.pausedDisplays = [Self.first] }

        let cards = nowPlaying(library: library, state: paused, connected: [Self.first], render: nil, host: Self.host, now: Self.now)

        #expect(cards.map(\.status) == ["Paused"])
    }

    @Test func `under Pause All a card reads paused at once, before a render state carries it`() throws {
        let library = try Self.library()
        let state = Self.state()
        let live = RenderState.make(library: library, state: state, connected: [Self.first], conditions: nil, previous: nil)

        let cards = nowPlaying(
            library: library, state: state, connected: [Self.first], render: live, isPausedAll: true, host: Self.host, now: Self.now
        )

        #expect(cards.map(\.status) == ["Paused"])
        #expect(cards.map(\.isPlaying) == [false])
    }

    // MARK: What each card shows

    @Test func `one card per connected display, in their order, with what each shows`() throws {
        let library = try Self.library()
        let state = Self.state {
            $0.assignments[Self.second] = .playlist(.numbered(1))
            $0.rotation[Self.second] = RotationState(current: .numbered(2), position: 1)
        }

        let cards = nowPlaying(library: library, state: state, connected: [Self.second, Self.first], host: Self.host, now: Self.now)

        #expect(cards.map(\.display) == [Self.second, Self.first])
        #expect(cards.map(\.wallpaper) == [library[.numbered(2)], library[.numbered(1)]])
        #expect(cards.map(\.playlist) == [.numbered(1), nil])
    }

    static let skips: [Row<AppState, Bool>] = [
        Row("a playlist of two can skip", state { $0.assignments[first] = .playlist(.numbered(1)) }, true),
        Row("a playlist with one wallpaper left in the library cannot", state { $0.assignments[first] = .playlist(.numbered(2)) }, false),
        Row("one wallpaper cannot", state(), false),
        Row("no wallpaper cannot", state { $0.assignments = [:] }, false),
    ]

    @Test(arguments: skips)
    func `skipping is only for a playlist of at least two`(row: Row<AppState, Bool>) throws {
        #expect(try Self.card(Situation(state: row.input)).canSkip == row.expected)
    }
}

// MARK: A wallpaper whose files have gone

extension NowPlayingTests {
    @Test func `a card whose wallpaper's files have gone says so, whatever the pause`() throws {
        let library = try Self.library()
        let state = Self.state()
        let live = RenderState.make(library: library, state: state, connected: [Self.first], conditions: nil, previous: nil)

        for isPausedAll in [false, true] {
            let cards = nowPlaying(
                library: library, state: state, connected: [Self.first], render: live, isPausedAll: isPausedAll,
                host: Self.host, now: Self.now, hasFiles: { _ in false }
            )

            #expect(cards.map(\.status) == ["Files missing"])
            #expect(cards.map(\.isPlaying) == [false])
        }
    }

    @Test func `a card whose wallpaper has its files plays as before`() throws {
        let library = try Self.library()
        let state = Self.state()
        let live = RenderState.make(library: library, state: state, connected: [Self.first], conditions: nil, previous: nil)

        let cards = nowPlaying(
            library: library, state: state, connected: [Self.first], render: live, host: Self.host, now: Self.now, hasFiles: { _ in true }
        )

        #expect(cards.map(\.status) == [nil])
        #expect(cards.map(\.isPlaying) == [true])
    }
}
