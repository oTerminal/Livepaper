import Foundation
import LivepaperCore
import LivepaperScene
import QuartzCore
import Synchronization
import Testing
@testable import LivepaperPlayback

// A scene stopped by a pause, a suspend or a still keeps its own last picture in the Metal slot,
// never its poster stretched over the display, and goes on from where it stopped; and what may
// follow a scene, playing or held still.

/// Counts the times the Metal slot is hidden while it is watched. Hidden between two pictures
/// of a scene, it shows the poster under it for a moment: a flash.
final class SlotHides: Sendable {
    private let hidden = Mutex(0)

    var count: Int { hidden.withLock(\.self) }

    func watch(_ slot: CALayer) -> NSKeyValueObservation {
        slot.observe(\.opacity, options: [.new]) { [self] _, change in
            if change.newValue == 0 { hidden.withLock { $0 += 1 } }
        }
    }
}

extension SurfacePlayback {
    /// One of the supervisor's calls, as it makes it.
    func apply(_ call: SurfaceCall) async {
        switch call {
        case .show(let wallpaper, let crossfade): await show(wallpaper, crossfade: crossfade)
        case .holdStill(let wallpaper): await holdStill(poster: wallpaper)
        case .showNothing: await showNothing()
        case .pause: await pause()
        case .resume: await resume()
        case .suspend: await suspend()
        }
    }
}

extension SurfacePlayerTests {
    // MARK: Stopping a scene

    /// How a scene is stopped: a pause (a pause rule, the user's pause of one display, or Pause
    /// All), a suspend, or the stopped render state (Quit).
    enum Stop: Sendable {
        case pause
        case suspend
        case holdStill
    }

    struct Stopped: Sendable {
        var state: SurfacePlaybackState
        /// The scene's drawing is kept, so that going on needs no load.
        var keepsDrawing: Bool
    }

    nonisolated static let stops: [Row<Stop, Stopped>] = [
        Row("a pause keeps the scene loaded", .pause, Stopped(state: .paused, keepsDrawing: true)),
        Row("a suspend lets the scene go", .suspend, Stopped(state: .suspended, keepsDrawing: false)),
        Row("a still lets the scene go, its poster under the picture", .holdStill, Stopped(state: .still, keepsDrawing: false)),
    ]

    func stop(_ player: SurfacePlayer, _ scene: SurfaceWallpaper, by stop: Stop) async {
        switch stop {
        case .pause: await player.pause()
        case .suspend: await player.suspend()
        case .holdStill: await player.holdStill(poster: scene)
        }
    }

    @Test(arguments: stops)
    func `a scene stopped keeps its last picture in the Metal slot, and no display link draws`(row: Row<Stop, Stopped>) async {
        let player = player()
        let scene = scene()
        await player.show(scene, crossfade: false)

        await stop(player, scene, by: row.input)

        #expect(player.state == row.expected.state)
        #expect(player.wallpaper == scene)
        #expect(player.layers.tree.scene.opacity == 1, "the scene's own picture, never its poster stretched over the display")
        #expect(player.layers.state == .still, "the poster is under the slot, for whatever hides it later")
        #expect(await eventually { (alive(scene) == 1) == row.expected.keepsDrawing })
        #expect(player.engine.folder == scene.scene?.folder, "the scene and its time are remembered")
        #expect(await player.engine.displayedPictures(over: .milliseconds(200)).asked == 0)
    }

    @Test(arguments: stops)
    func `a scene stopped goes on from the time it stopped at, its picture up throughout`(row: Row<Stop, Stopped>) async {
        let player = player()
        let scene = scene()
        await player.show(scene, crossfade: false)
        // A layer on no screen is given a few frames, then none: enough for the scene to be past its start.
        _ = await eventually { times(scene).count >= 2 }
        let hides = SlotHides()
        let watch = hides.watch(player.layers.tree.scene)
        defer { watch.invalidate() }
        let reached = player.engine.sceneTime
        await stop(player, scene, by: row.input)
        let drawnBefore = times(scene).count

        // What the supervisor asks of the surface when its display plays again (Resume All, the pause rule gone).
        for call in surfaceCalls(toReach: .playback(scene, .play), from: player.state, showing: player.wallpaper) {
            await player.apply(call)
        }

        #expect(player.state == .playing)
        #expect(player.layers.tree.scene.opacity == 1)
        #expect(hides.count == 0, "the slot is never hidden, so the poster never shows through")
        #expect(made(scene) == (row.expected.keepsDrawing ? 1 : 2))
        #expect(player.engine.sceneTime >= reached, "scene time goes on from \(reached) s")
        try? await Task.sleep(for: .milliseconds(200))
        let after = Array(times(scene).dropFirst(drawnBefore))
        #expect(after.allSatisfy { $0 >= reached }, "no picture goes back to the start: \(after.prefix(3)) after \(reached) s")
    }

    @Test func `a still of a scene with no picture yet holds its poster, the slot hidden`() async {
        let player = player()
        let scene = scene()
        let gate = CountedDrawing.holdNextLoad(of: scene)
        defer { gate.open() }
        let showing = Task { await player.show(scene, crossfade: false) }
        #expect(await eventually { gate.hasArrived })

        await player.holdStill(poster: scene)
        gate.open()
        await showing.value

        #expect(player.state == .still)
        #expect(player.layers.tree.scene.opacity == 0)
        #expect(await eventually { alive(scene) == 0 })
        #expect(player.engine.folder == nil)
    }

    // MARK: What follows a scene

    /// What the supervisor may ask of a surface after a scene.
    enum Next: Sendable {
        case stillOfTheScene
        case stillRefitted
        case stillOfAnother
        case nothing
        case video
    }

    /// Whether the slot keeps the scene's picture.
    nonisolated static let afterAScene: [Row<Next, Bool>] = [
        Row("a still of the scene keeps its picture up", .stillOfTheScene, true),
        Row("a still of the scene in a new presentation keeps its picture up, laid out anew", .stillRefitted, true),
        Row("a still of another wallpaper hides the slot", .stillOfAnother, false),
        Row("nothing hides the slot", .nothing, false),
        Row("a video hides the slot", .video, false),
    ]

    @Test(arguments: [false, true], afterAScene)
    func `after a scene, playing or held still, only a still of that scene keeps the slot up`(heldStill: Bool, row: Row<Next, Bool>) async {
        let player = player()
        let scene = scene()
        await player.show(scene, crossfade: false)
        if heldStill { await player.holdStill(poster: scene) }
        var refitted = scene
        refitted.presentation = Presentation(fit: .fit)

        switch row.input {
        case .stillOfTheScene: await player.holdStill(poster: scene)
        case .stillRefitted: await player.holdStill(poster: refitted)
        case .stillOfAnother: await player.holdStill(poster: .numbered(1))
        case .nothing: await player.showNothing()
        // A video that cannot be played holds its poster, as it always has; the scene is gone all the same.
        case .video: await player.show(.numbered(1), crossfade: true)
        }

        #expect((player.layers.tree.scene.opacity == 1) == row.expected)
        #expect(await eventually { alive(scene) == 0 }, "the scene's drawing is let go")
        #expect(await player.engine.displayedPictures(over: .milliseconds(200)).asked == 0, "no display link draws")
        if row.expected {
            #expect(player.state == .still)
            #expect(player.engine.folder == scene.scene?.folder)
        } else {
            #expect(player.wallpaper?.scene == nil)
            #expect(player.engine.folder == nil, "the scene and its time are forgotten")
        }
        if row.input == .stillRefitted {
            #expect(player.wallpaper == refitted)
            let frame = player.layers.tree.scene.frame
            #expect(abs(frame.width - Self.geometry.size.width) < 0.001, "fitted, the scene is as wide as the surface: \(frame)")
        }
    }

    @Test func `another scene after one held still starts from its own beginning, over its own poster`() async {
        let player = player()
        let first = scene()
        let second = scene()
        await player.show(first, crossfade: false)
        _ = await eventually { times(first).count >= 2 }
        await player.holdStill(poster: first)
        let hides = SlotHides()
        let watch = hides.watch(player.layers.tree.scene)
        defer { watch.invalidate() }

        await player.show(second, crossfade: false)

        #expect(hides.count == 1, "the first scene's picture goes once the second's poster is under it")
        #expect(player.wallpaper == second)
        #expect(player.state == .playing)
        #expect(player.layers.tree.scene.opacity == 1)
        #expect(player.engine.folder == second.scene?.folder)
        #expect(made(second) == 1)
        #expect((times(second).first ?? 0) == 0, "its first picture is its first moment")
    }
}
