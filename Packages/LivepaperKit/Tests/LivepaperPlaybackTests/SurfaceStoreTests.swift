import Foundation
import Testing
import LivepaperCore
import LivepaperPlayback

struct SurfaceStoreTests {
    /// Something the agent does, or the clock running on, at a number of seconds after launch.
    enum Event: Sendable {
        case acquire(Int, display: Int, preview: Bool = false)
        case invalidate(Int)
        case tick
    }

    struct Story: Sendable {
        var events: [(seconds: TimeInterval, event: Event)]

        static func of(_ events: (TimeInterval, Event)...) -> Story {
            Story(events: events.map { (seconds: $0.0, event: $0.1) })
        }
    }

    static func told(_ story: Story) -> (effects: [SurfaceStoreEffect], store: SurfaceStore) {
        var store = SurfaceStore()
        var effects: [SurfaceStoreEffect] = []
        for (seconds, event) in story.events {
            let now = Moment.after(seconds)
            switch event {
            case .acquire(let surface, let display, let preview):
                effects.append(store.acquire(.numbered(surface), display: .numbered(display), isPreview: preview))
            case .invalidate(let surface):
                store.invalidate(.numbered(surface), at: now)
            case .tick:
                effects += store.tearDown(at: now)
            }
        }
        return (effects, store)
    }

    static let stories: [Row<Story, [SurfaceStoreEffect]>] = [
        Row("a first acquire makes a context", .of((0, .acquire(1, display: 1))), [.create(.numbered(1))]),
        Row(
            "an acquire of a live surface reuses its context",
            .of((0, .acquire(1, display: 1)), (5, .acquire(1, display: 1))),
            [.create(.numbered(1)), .reuse(.numbered(1))]
        ),
        Row(
            "a re-acquire within 15 s reuses the context",
            .of((0, .acquire(1, display: 1)), (10, .invalidate(1)), (24.9, .acquire(1, display: 1)), (60, .tick)),
            [.create(.numbered(1)), .reuse(.numbered(1))]
        ),
        Row(
            "an invalidated surface is kept for 15 s",
            .of((0, .acquire(1, display: 1)), (10, .invalidate(1)), (24.9, .tick)),
            [.create(.numbered(1))]
        ),
        Row(
            "an invalidated surface is torn down after 15 s",
            .of((0, .acquire(1, display: 1)), (10, .invalidate(1)), (25, .tick)),
            [.create(.numbered(1)), .tearDown(.numbered(1))]
        ),
        Row(
            "a surface torn down is made anew when the agent asks again",
            .of((0, .acquire(1, display: 1)), (10, .invalidate(1)), (25, .tick), (30, .acquire(1, display: 1))),
            [.create(.numbered(1)), .tearDown(.numbered(1)), .create(.numbered(1))]
        ),
        Row(
            "each invalidated surface has its own 15 s",
            .of(
                (0, .acquire(1, display: 1)), (0, .acquire(2, display: 1, preview: true)),
                (10, .invalidate(2)), (20, .invalidate(1)), (26, .tick), (36, .tick)
            ),
            [.create(.numbered(1)), .create(.numbered(2)), .tearDown(.numbered(2)), .tearDown(.numbered(1))]
        ),
        Row(
            "a replug is a new surface for the same display, and the old one goes at its timeout",
            .of((0, .acquire(1, display: 1)), (10, .invalidate(1)), (16, .acquire(2, display: 1)), (25, .tick)),
            [.create(.numbered(1)), .create(.numbered(2)), .tearDown(.numbered(1))]
        ),
        Row("a tick with nothing invalidated tears nothing down", .of((0, .acquire(1, display: 1)), (60, .tick)), [.create(.numbered(1))]),
    ]

    @Test(arguments: stories)
    func `keeps contexts through the agent's reconnects`(row: Row<Story, [SurfaceStoreEffect]>) {
        #expect(Self.told(row.input).effects == row.expected)
    }

    @Test func `the next teardown is the earliest grace to run out`() {
        let (_, store) = Self.told(.of(
            (0, .acquire(1, display: 1)), (0, .acquire(2, display: 2)), (0, .acquire(3, display: 3)),
            (10, .invalidate(2)), (12, .invalidate(1))
        ))

        #expect(store.nextTeardown == Moment.after(25))
    }

    @Test func `a re-acquire cancels its teardown`() {
        let (_, store) = Self.told(.of((0, .acquire(1, display: 1)), (10, .invalidate(1)), (11, .acquire(1, display: 1))))

        #expect(store.nextTeardown == nil)
        #expect(store.entries[.numbered(1)]?.isLive == true)
    }

    @Test func `an unknown surface cannot be invalidated`() {
        var store = SurfaceStore()

        let known = store.invalidate(.numbered(9), at: Moment.launch)

        #expect(!known)
        #expect(store.nextTeardown == nil)
    }

    // MARK: Which surface shows what

    static let state = RenderState(
        generation: 3,
        displays: [.numbered(1, showing: 5), .numbered(2, showing: 6)],
        pauseRules: PauseRules(),
        conditions: nil
    )

    struct Lookup: Sendable {
        var story: Story
        var surface: Int
    }

    static let lookups: [Row<Lookup, SurfaceTarget>] = [
        Row(
            "a surface shows its display's wallpaper",
            Lookup(story: .of((0, .acquire(1, display: 2))), surface: 1),
            .playback(.numbered(6), .play)
        ),
        Row(
            "a new surface for a known display gets that display's wallpaper",
            Lookup(story: .of((0, .acquire(1, display: 1)), (10, .invalidate(1)), (25, .tick), (97, .acquire(2, display: 1))), surface: 2),
            .playback(.numbered(5), .play)
        ),
        Row(
            "the preview shows its display's wallpaper",
            Lookup(story: .of((0, .acquire(1, display: 1)), (1, .acquire(2, display: 1, preview: true))), surface: 2),
            .playback(.numbered(5), .play)
        ),
        Row("a display absent from the state shows nothing", Lookup(story: .of((0, .acquire(1, display: 3))), surface: 1), .nothing),
        Row("a surface the store does not know shows nothing", Lookup(story: .of((0, .acquire(1, display: 1))), surface: 7), .nothing),
    ]

    @Test(arguments: lookups)
    func `a surface shows its display's assignment`(row: Row<Lookup, SurfaceTarget>) {
        let store = Self.told(row.input.story).store

        let target = store.target(
            for: .numbered(row.input.surface), in: .state(Self.state), location: testLibrary,
            host: HostCapabilities(showsLockScreen: true), now: Moment.after(100)
        )

        #expect(target == row.expected)
    }

    // MARK: The preview and the heartbeat

    static let desktops: [Row<Story, Bool>] = [
        Row("no surface is no desktop", .of(), false),
        Row("a desktop surface is acquired", .of((0, .acquire(1, display: 1))), true),
        Row("the Settings preview alone is not the desktop", .of((0, .acquire(1, display: 1, preview: true))), false),
        Row("an invalidated desktop surface no longer counts", .of((0, .acquire(1, display: 1)), (5, .invalidate(1))), false),
        Row(
            "a desktop surface re-acquired within its grace counts again",
            .of((0, .acquire(1, display: 1)), (5, .invalidate(1)), (6, .acquire(1, display: 1))),
            true
        ),
    ]

    @Test(arguments: desktops)
    func `knows whether a desktop surface is live`(row: Row<Story, Bool>) {
        #expect(Self.told(row.input).store.hasLiveDesktopSurface == row.expected)
    }

    @Test func `remembers the preview flag and the mode`() {
        var store = Self.told(.of((0, .acquire(1, display: 1)), (0, .acquire(2, display: 1, preview: true)))).store

        let updated = store.update(.numbered(1), mode: .locked)
        let unknown = store.update(.numbered(9), mode: .locked)

        #expect(updated)
        #expect(!unknown)
        #expect(store.entries[.numbered(1)] == SurfaceStore.Entry(display: .numbered(1), isPreview: false, mode: .locked))
        #expect(store.entries[.numbered(2)] == SurfaceStore.Entry(display: .numbered(1), isPreview: true, mode: .desktop))
        #expect(store.liveSurfaces(on: .numbered(1)) == [.numbered(1), .numbered(2)])
    }
}
