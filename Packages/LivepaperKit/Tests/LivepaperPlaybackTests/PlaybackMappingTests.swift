import Foundation
import Testing
import LivepaperCore
import LivepaperPlayback

struct PlaybackMappingTests {
    /// A surface as the mapping finds it, and what it is to reach.
    struct Situation: Sendable {
        var target: SurfaceTarget
        var state: SurfacePlaybackState
        var showing: SurfaceWallpaper?

        static func reach(_ target: SurfaceTarget, from state: SurfacePlaybackState, showing: SurfaceWallpaper? = nil) -> Situation {
            Situation(target: target, state: state, showing: showing)
        }
    }

    static let one = SurfaceWallpaper.numbered(1)
    static let two = SurfaceWallpaper.numbered(2)
    static let oneFitted = SurfaceWallpaper.numbered(1, presentation: .fit)
    static let oneLouder = SurfaceWallpaper.numbered(1, volume: 0.5)

    static func play(_ wallpaper: SurfaceWallpaper) -> SurfaceTarget { .playback(wallpaper, .play) }
    static func paused(_ wallpaper: SurfaceWallpaper) -> SurfaceTarget { .playback(wallpaper, .pause(.desktopCovered)) }
    static func suspended(_ wallpaper: SurfaceWallpaper) -> SurfaceTarget { .playback(wallpaper, .suspend(.displayAsleep)) }

    static let rows: [Row<Situation, [SurfaceCall]>] = [
        // Nothing to show: no render state, or none for this display.
        Row("nothing stays nothing", .reach(.nothing, from: .nothing), []),
        Row("nothing replaces a playing wallpaper", .reach(.nothing, from: .playing, showing: one), [.showNothing]),
        Row("nothing replaces a still", .reach(.nothing, from: .still, showing: one), [.showNothing]),
        Row("nothing releases a suspended surface", .reach(.nothing, from: .suspended, showing: one), [.showNothing]),

        // The stopped render state holds the poster.
        Row("a stopped state holds the poster of what was playing", .reach(.still(one), from: .playing, showing: one), [.holdStill(one)]),
        Row("a stopped state holds the poster from nothing", .reach(.still(one), from: .nothing), [.holdStill(one)]),
        Row("a stopped state holds a paused wallpaper's poster", .reach(.still(one), from: .paused, showing: one), [.holdStill(one)]),
        Row("a still that is already up stays", .reach(.still(one), from: .still, showing: one), []),
        Row("a still whose volume changed stays", .reach(.still(oneLouder), from: .still, showing: one), []),
        Row("a still of another wallpaper is replaced", .reach(.still(two), from: .still, showing: one), [.holdStill(two)]),
        Row(
            "a still is laid out again for a new presentation",
            .reach(.still(oneFitted), from: .still, showing: one),
            [.holdStill(oneFitted)]
        ),

        // Play.
        Row("play from nothing shows the wallpaper without a fade", .reach(play(one), from: .nothing), [.show(one, crossfade: false)]),
        Row(
            "play from its own still starts its video without a fade",
            .reach(play(one), from: .still, showing: one),
            [.show(one, crossfade: false)]
        ),
        Row("play from another still starts without a fade", .reach(play(two), from: .still, showing: one), [.show(two, crossfade: false)]),
        Row("play of what already plays does nothing", .reach(play(one), from: .playing, showing: one), []),
        Row("switching a surface that plays crossfades", .reach(play(two), from: .playing, showing: one), [.show(two, crossfade: true)]),
        Row(
            "a new presentation is changed in place",
            .reach(play(oneFitted), from: .playing, showing: one),
            [.show(oneFitted, crossfade: false)]
        ),
        Row(
            "a new volume is changed in place",
            .reach(play(oneLouder), from: .playing, showing: one),
            [.show(oneLouder, crossfade: false)]
        ),
        Row("play after pause resumes", .reach(play(one), from: .paused, showing: one), [.resume]),
        Row("play after suspend resumes", .reach(play(one), from: .suspended, showing: one), [.resume]),
        Row(
            "play of another wallpaper after pause switches without a fade",
            .reach(play(two), from: .paused, showing: one),
            [.show(two, crossfade: false)]
        ),
        Row(
            "play of another wallpaper after suspend switches",
            .reach(play(two), from: .suspended, showing: one),
            [.show(two, crossfade: false)]
        ),
        Row(
            "play with a new volume after pause changes it and plays",
            .reach(play(oneLouder), from: .paused, showing: one),
            [.show(oneLouder, crossfade: false)]
        ),

        // Pause keeps the readers.
        Row("pause stops a playing surface and keeps its readers", .reach(paused(one), from: .playing, showing: one), [.pause]),
        Row("pause of a paused surface does nothing", .reach(paused(one), from: .paused, showing: one), []),
        Row(
            "pause of a suspended surface opens its readers again, so it shows a picture",
            .reach(paused(one), from: .suspended, showing: one),
            [.resume, .pause]
        ),
        Row("pause never starts a video: nothing up holds the poster", .reach(paused(one), from: .nothing), [.holdStill(one)]),
        Row("pause leaves a still of the same wallpaper up", .reach(paused(one), from: .still, showing: one), []),
        Row("a new wallpaper while paused is held as its poster", .reach(paused(two), from: .playing, showing: one), [.holdStill(two)]),
        Row(
            "a new presentation while paused is laid out in place and stays paused",
            .reach(paused(oneFitted), from: .paused, showing: one),
            [.show(oneFitted, crossfade: false), .pause]
        ),
        Row("a new volume while paused waits for play", .reach(paused(oneLouder), from: .paused, showing: one), []),

        // Suspend releases them.
        Row("suspend releases a playing surface's readers", .reach(suspended(one), from: .playing, showing: one), [.suspend]),
        Row("suspend releases a paused surface's readers", .reach(suspended(one), from: .paused, showing: one), [.suspend]),
        Row("suspend of a suspended surface does nothing", .reach(suspended(one), from: .suspended, showing: one), []),
        Row("suspend never starts a video: nothing up holds the poster", .reach(suspended(one), from: .nothing), [.holdStill(one)]),
        Row("suspend leaves a still of the same wallpaper up", .reach(suspended(one), from: .still, showing: one), []),
        Row(
            "a new wallpaper while suspended is held as its poster",
            .reach(suspended(two), from: .suspended, showing: one),
            [.holdStill(two)]
        ),
        Row(
            "a new presentation while suspended is held as the poster, laid out anew",
            .reach(suspended(oneFitted), from: .suspended, showing: one),
            [.holdStill(oneFitted)]
        ),

        // A scene is mapped as a video is: the surface tells them apart.
        Row("a video playing switches to a scene", .reach(play(scene3), from: .playing, showing: one), [.show(scene3, crossfade: true)]),
        Row("a scene playing switches to a video", .reach(play(one), from: .playing, showing: scene3), [.show(one, crossfade: true)]),
        Row("a scene playing goes on", .reach(play(scene3), from: .playing, showing: scene3), []),
        Row("a scene pauses where a video would", .reach(paused(scene3), from: .playing, showing: scene3), [.pause]),
        Row("a scene suspends where a video would", .reach(suspended(scene3), from: .paused, showing: scene3), [.suspend]),
        Row("a suspended scene resumes", .reach(play(scene3), from: .suspended, showing: scene3), [.resume]),
        Row("a stopped state holds a scene's poster", .reach(.still(scene3), from: .playing, showing: scene3), [.holdStill(scene3)]),
    ]

    /// Wallpaper 3, a scene.
    static let scene3 = SurfaceWallpaper.scene(3)

    @Test(arguments: rows)
    func `maps a decision onto a surface`(row: Row<Situation, [SurfaceCall]>) {
        let calls = surfaceCalls(toReach: row.input.target, from: row.input.state, showing: row.input.showing)

        #expect(calls == row.expected)
    }

    @Test func `a scene's display is resolved to the scene's folder and size, a video's to no scene`() throws {
        let id = WallpaperID.numbered(3)
        var display = RenderState.Display.numbered(1, showing: 3)
        display.optimisedCopy = .known("wallpapers/\(id)/scene.pkg")
        display.scene = WallpaperScene(project: .known("wallpapers/\(id)/project.json"), width: 1920, height: 1080)

        let wallpaper = SurfaceWallpaper(display, in: testLibrary)

        let scene = try #require(wallpaper.scene)
        #expect(scene.folder.path == testLibrary.wallpapers.appending(path: id.description).path)
        #expect(scene.size == Size(width: 1920, height: 1080))
        #expect(wallpaper.video == testLibrary.url(for: .known("wallpapers/\(id)/scene.pkg")))
        #expect(SurfaceWallpaper(.numbered(1), in: testLibrary).scene == nil)
    }
}

/// When a decision that sensed conditions made is taken again.
struct DecisionExpiryTests {
    static let sensed = PlaybackConditions(sensedAt: Moment.launch, now: Moment.after(1))

    static func conditions(_ change: (inout PlaybackConditions) -> Void) -> PlaybackConditions {
        var conditions = sensed
        change(&conditions)
        return conditions
    }

    static let pausing: [Row<PlaybackConditions, Bool>] = [
        Row("a covered desktop's pause expires", conditions { $0.desktopCovered = true }, true),
        Row("a sleeping display's suspend expires", conditions { $0.displayAsleep = true }, true),
        Row("Low Power Mode's suspend expires", conditions { $0.lowPowerMode = true }, true),
        Row("conditions that play expire into play, so nothing is scheduled", sensed, false),
        Row("the user's pause never expires", conditions { $0.userPaused = true; $0.desktopCovered = true }, false),
    ]

    @Test(arguments: pausing)
    func `decides again when the conditions behind a pause expire`(row: Row<PlaybackConditions, Bool>) {
        let rules = PauseRules()
        let host = HostCapabilities(showsLockScreen: true)
        let decision = decidePlayback(row.input, rules: rules, host: host)

        let expiry = decisionExpiry(of: decision, conditions: row.input)

        #expect((expiry != nil) == row.expected)
    }

    @Test func `the expiry is the first moment the decision changes`() throws {
        let rules = PauseRules()
        let host = HostCapabilities(showsLockScreen: true)
        var conditions = Self.conditions { $0.desktopCovered = true }
        let decision = decidePlayback(conditions, rules: rules, host: host)

        let expiry = try #require(decisionExpiry(of: decision, conditions: conditions))

        #expect(expiry > Moment.after(30))
        #expect(expiry < Moment.after(30.001))
        conditions.now = Moment.after(30)
        #expect(decidePlayback(conditions, rules: rules, host: host) == .pause(.desktopCovered), "30 s old still counts")
        conditions.now = expiry
        #expect(decidePlayback(conditions, rules: rules, host: host) == .play)
    }
}
