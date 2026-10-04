import Foundation
import LivepaperCore
import LivepaperScene
import Metal
import os
import Synchronization
import Testing
@testable import LivepaperPlayback

/// A drawing that draws nothing and counts itself, by the folder it was made for, so that
/// tests running side by side do not see each other's.
final class CountedDrawing: SceneDrawing {
    static let made = Mutex<[URL: Int]>([:])
    static let alive = Mutex<[URL: Int]>([:])
    /// The scene times each folder's pictures were drawn at, in order.
    static let times = Mutex<[URL: [Double]]>([:])
    /// The next load of each folder here waits at its gate.
    static let gates = Mutex<[URL: LoadGate]>([:])
    let folder: URL

    required init(folder: URL, device: any MTLDevice) throws {
        if let gate = Self.gates.withLock({ $0.removeValue(forKey: folder) }) { gate.hold() }
        self.folder = folder
        Self.made.withLock { $0[folder, default: 0] += 1 }
        Self.alive.withLock { $0[folder, default: 0] += 1 }
    }

    /// Holds the next load of `wallpaper`'s scene until the gate is opened, so that a request can come while it loads.
    static func holdNextLoad(of wallpaper: SurfaceWallpaper) -> LoadGate {
        let gate = LoadGate()
        gates.withLock { $0[wallpaper.scene?.folder ?? URL(filePath: "/")] = gate }
        return gate
    }

    deinit {
        Self.alive.withLock { $0[folder, default: 0] -= 1 }
    }

    func draw(into texture: any MTLTexture, on commandBuffer: any MTLCommandBuffer, at time: Double) {
        Self.times.withLock { $0[folder, default: []].append(time) }
    }

    func resize(width: Int, height: Int) {}
}

/// Where a scene's load waits: on the load queue, until the test opens it. Opening it twice does no harm.
final class LoadGate: Sendable {
    private let arrived = Atomic(false)
    private let opened = Atomic(false)
    private let door = DispatchSemaphore(value: 0)

    /// The load is at the gate.
    var hasArrived: Bool { arrived.load(ordering: .acquiring) }

    func hold() {
        arrived.store(true, ordering: .releasing)
        door.wait()
    }

    func open() {
        guard opened.compareExchange(expected: false, desired: true, ordering: .acquiringAndReleasing).exchanged else { return }
        door.signal()
    }
}

/// A drawing that refuses every scene.
final class RefusingDrawing: SceneDrawing {
    struct Refused: Error {}

    required init(folder: URL, device: any MTLDevice) throws {
        throw Refused()
    }

    func draw(into texture: any MTLTexture, on commandBuffer: any MTLCommandBuffer, at time: Double) {}
    func resize(width: Int, height: Int) {}
}

/// A surface's player on a real layer tree, with drawings that draw nothing: whether a scene
/// is up, playing, paused or let go, and the Metal slot shown or hidden accordingly. What it
/// looks like on the desktop is checked on screen. Needs a GPU for the scene engine.
@MainActor
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct SurfacePlayerTests {
    static let geometry = SurfaceGeometry(size: Size(width: 800, height: 500), scale: 2)
    static let logger = Logger(subsystem: "app.livepaper.tests", category: "scene")

    func player(_ drawing: any SceneDrawing.Type = CountedDrawing.self) -> SurfacePlayer {
        let layers = SurfaceLayers(
            id: .numbered(Int.random(in: 1...999_999)), geometry: Self.geometry, logger: Self.logger,
            prepareVideoLayer: { _ in }
        )
        return SurfacePlayer(layers: layers, drawingType: drawing, logger: Self.logger)
    }

    /// A scene of its own folder, so that its drawings are counted apart from every other test's.
    func scene() -> SurfaceWallpaper {
        var wallpaper = SurfaceWallpaper.scene(3)
        wallpaper.scene?.folder = URL(filePath: "/tmp/livepaper-tests/\(UUID().uuidString)", directoryHint: .isDirectory)
        return wallpaper
    }

    func alive(_ wallpaper: SurfaceWallpaper) -> Int {
        CountedDrawing.alive.withLock { $0[wallpaper.scene?.folder ?? URL(filePath: "/"), default: 0] }
    }

    func made(_ wallpaper: SurfaceWallpaper) -> Int {
        CountedDrawing.made.withLock { $0[wallpaper.scene?.folder ?? URL(filePath: "/"), default: 0] }
    }

    func times(_ wallpaper: SurfaceWallpaper) -> [Double] {
        CountedDrawing.times.withLock { $0[wallpaper.scene?.folder ?? URL(filePath: "/"), default: []] }
    }

    /// A drawing let go may still be in the frame the render thread is on; that frame ends at once.
    func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0..<100 {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @Test func `a scene is drawn in the Metal slot over its poster`() async {
        let player = player()
        let scene = scene()

        await player.show(scene, crossfade: false)

        #expect(player.state == .playing)
        #expect(player.wallpaper == scene)
        #expect(player.layers.state == .still, "the poster is held under the slot, the video's decoders released")
        #expect(player.layers.tree.scene.opacity == 1)
        #expect(made(scene) == 1 && alive(scene) == 1)
        #expect(player.layers.tree.scene.drawableSize.width > 0)
    }

    @Test func `a scene pauses and resumes keeping what it loaded, and a suspend lets it go`() async {
        let player = player()
        let scene = scene()
        await player.show(scene, crossfade: false)

        await player.pause()
        #expect(player.state == .paused)
        #expect(alive(scene) == 1)
        await player.resume()
        #expect(player.state == .playing)
        #expect(made(scene) == 1)

        await player.suspend()
        #expect(player.state == .suspended)
        #expect(await eventually { alive(scene) == 0 })
        await player.resume()
        #expect(player.state == .playing)
        #expect(made(scene) == 2 && alive(scene) == 1)
        #expect(player.layers.tree.scene.opacity == 1, "the last picture stays up through all of it")
    }

    @Test func `the watchdog counts a playing scene, and nothing of a paused one`() async throws {
        let player = player()
        await player.show(scene(), crossfade: false)

        let count = try #require(await player.displayedPictures(over: .seconds(1)))
        #expect(count.expected == 30)
        await whereTheSystemCallsTheDisplayLink {
            #expect(count.displayed > 0 && count.fed > 0 && (count.asked ?? 0) > 0, "the scene's pictures are drawn and counted: \(count)")
        }
        await player.pause()
        #expect(await player.displayedPictures(over: .milliseconds(100)) == nil)
    }

    @Test func `a scene still loading is not counted, so a slow load never climbs the ladder`() async throws {
        let player = player()
        let scene = scene()
        let gate = CountedDrawing.holdNextLoad(of: scene)
        defer { gate.open() }

        let showing = Task { await player.show(scene, crossfade: false) }
        #expect(await eventually { gate.hasArrived })
        #expect(player.state == .playing, "asked to play, as the supervisor sees it")
        #expect(await player.displayedPictures(over: .milliseconds(100)) == nil)
        gate.open()
        await showing.value

        let count = try #require(await player.displayedPictures(over: .milliseconds(300)))
        await whereTheSystemCallsTheDisplayLink {
            #expect(count.displayed > 0)
        }
    }

    @Test func `a video asked for while a scene loads again leaves nothing loaded or drawing in the hidden slot`() async {
        let player = player()
        let scene = scene()
        await player.show(scene, crossfade: false)
        let gate = CountedDrawing.holdNextLoad(of: scene)
        defer { gate.open() }

        let reloading = Task { await player.recover(.rebuildPipeline) }
        #expect(await eventually { gate.hasArrived })
        await player.show(.numbered(1), crossfade: false)
        gate.open()
        await reloading.value

        #expect(player.wallpaper?.scene == nil)
        #expect(player.layers.tree.scene.opacity == 0)
        #expect(!player.engine.isLoaded, "the scene loaded for nobody is let go")
        #expect(await eventually { alive(scene) == 0 })
        #expect(await player.engine.displayedPictures(over: .milliseconds(200)).asked == 0, "no display link draws it")
    }

    @Test func `a pause while a scene loads again leaves it paused, its link not started`() async {
        let player = player()
        let scene = scene()
        await player.show(scene, crossfade: false)
        let gate = CountedDrawing.holdNextLoad(of: scene)
        defer { gate.open() }

        let reloading = Task { await player.recover(.rebuildPipeline) }
        #expect(await eventually { gate.hasArrived })
        await player.pause()
        gate.open()
        await reloading.value

        #expect(player.state == .paused)
        #expect(await player.engine.displayedPictures(over: .milliseconds(200)).asked == 0, "no display link draws it")
        await player.resume()
        #expect(player.state == .playing)
        #expect(player.layers.tree.scene.opacity == 1)
        await whereTheSystemCallsTheDisplayLink {
            #expect(await player.engine.displayedPictures(over: .milliseconds(200)).asked ?? 0 > 0)
        }
    }

    @Test func `another scene replaces the one up, and the same one with a new presentation stays up`() async {
        let player = player()
        let first = scene()
        let second = scene()
        await player.show(first, crossfade: false)

        var fitted = first
        fitted.presentation = Presentation(fit: .fit)
        await player.show(fitted, crossfade: false)
        #expect(made(first) == 1)
        #expect(player.wallpaper == fitted)

        await player.show(second, crossfade: true)
        #expect(await eventually { alive(first) == 0 })
        #expect(made(second) == 1)
        #expect(player.wallpaper == second)
        #expect(player.state == .playing)
    }

    @Test func `a scene that cannot be drawn holds its poster`() async {
        let player = player(RefusingDrawing.self)

        await player.show(scene(), crossfade: false)

        #expect(player.state == .still)
        #expect(player.layers.tree.scene.opacity == 0)
    }
}
