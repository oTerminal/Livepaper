// The display link on a thread of its own with its own run loop, and the layer shown by its opacity
// once it is in the tree, follow the spike.

import Foundation
import LivepaperScene
import Metal
import os
import QuartzCore
import Synchronization

/// Draws one surface's scene into the tree's Metal slot, a frame at a time, at
/// `LivepaperScene.framesPerSecond`.
///
/// `CAMetalDisplayLink` drives it, on a render thread with a run loop of its own
/// (`SceneRenderThread`), shared by every surface: the link fires there and
/// the scene is drawn there, never on the main actor, whose work must not wait
/// on a frame, and never on Swift's cooperative pool. Loading a scene can take
/// a while, and happens on a queue of its own. What the owner calls runs on the
/// owner's actor; what the threads share is behind one lock.
///
/// Scene time runs only while the engine draws (`SceneClock`). Pausing stops the
/// link and keeps the scene; suspending also lets the scene go, and a resume
/// loads it again; stopping forgets it and its time. The last picture stays on
/// the layer through all of them.
public final class SceneEngine: @unchecked Sendable {
    public let surface: SurfaceID
    private let layer: CAMetalLayer
    private let drawingType: DrawingType
    private let logger: Logger
    private let shared = Mutex(Shared())
    private let linkTarget = LinkTarget()

    private struct Shared {
        var drawing: DrawingBox?
        var folder: URL?
        var clock = SceneClock()
        var tally = SceneTally()
        /// Counts starts and stops: a link of an earlier run draws nothing.
        var run = 0
        /// Counts loads, stops and suspends: a load that finishes after a later one of them is let go.
        var loads = 0
        /// Started with a scene loaded, and not paused since: the watchdog may count it.
        var running = false
        var link: LinkBox?
        var drawnSize: SIMD2<Int>?
        var startedAt: ContinuousClock.Instant?
        var firstPictureDrawn = false
    }

    /// The scene's sounds, on the owner's actor, and the wallpaper's volume they play at.
    private var soundtrack: SceneSoundtrack?
    private var volume = 0.0
    /// Where the pointer is over the surface's display, read on the render thread each frame.
    private let pointer: (@Sendable () -> SIMD2<Float>?)?

    /// `layer` is the tree's Metal slot; `drawingType` what draws the scene (`WallpaperEngineScene` in the extension).
    init(
        surface: SurfaceID, layer: CAMetalLayer, drawingType: any SceneDrawing.Type, logger: Logger,
        pointer: (@Sendable () -> SIMD2<Float>?)? = nil
    ) {
        self.surface = surface
        self.layer = layer
        self.drawingType = DrawingType(type: drawingType)
        self.logger = logger
        self.pointer = pointer
        linkTarget.engine = self
    }

    /// The wallpaper's volume, 0 to 1, for the scene's sounds.
    func setVolume(_ volume: Double) {
        self.volume = volume
        soundtrack?.setVolume(volume)
    }

    var isLoaded: Bool { shared.withLock { $0.drawing != nil } }

    /// The scene in `folder` is the one loaded.
    func holds(_ folder: URL) -> Bool { shared.withLock { $0.folder == folder && $0.drawing != nil } }

    /// Drawing: started with a scene loaded and not paused since, so its pictures are the watchdog's to count.
    var isRunning: Bool { shared.withLock(\.running) }

    // MARK: Loading

    /// Loads the scene in `folder`, unless it is the one loaded already. False
    /// when it cannot be drawn: no GPU, or a scene the drawing refuses; and
    /// when a stop, a suspend or another load came while it loaded, which have
    /// the last word, so that what it made is let go and never drawn.
    func load(_ folder: URL) async -> Bool {
        if holds(folder) { return true }
        guard let gpu = SceneGPU.shared else {
            logger.error("\(EngineLog.noMetalDevice(self.surface), privacy: .public)")
            return false
        }
        layer.device = gpu.device
        let load = shared.withLock { shared -> Int in
            shared.loads += 1
            return shared.loads
        }
        let type = drawingType
        let clock = ContinuousClock()
        let started = clock.now
        let made: Result<DrawingBox, any Error> = await withCheckedContinuation { continuation in
            sceneLoadQueue.async {
                continuation.resume(returning: Result {
                    let drawing = try type.type.init(folder: folder, device: gpu.device)
                    return DrawingBox(drawing, soundtrack: drawing.makeSoundtrack())
                })
            }
        }
        switch made {
        case .success(let drawing):
            let isWanted = shared.withLock { shared -> Bool in
                guard shared.loads == load else { return false }
                shared.drawing = drawing
                shared.folder = folder
                shared.drawnSize = nil
                return true
            }
            guard isWanted else { return false }
            soundtrack?.stop()
            soundtrack = drawing.soundtrack
            soundtrack?.setVolume(volume)
            let took = (clock.now - started) / .milliseconds(1)
            logger.notice("\(EngineLog.sceneLoaded(self.surface, folder, by: type.type, milliseconds: took), privacy: .public)")
            let notes = drawing.drawing.notes
            if !notes.isEmpty { logger.notice("\(EngineLog.sceneNotes(self.surface, folder, notes), privacy: .public)") }
            return true
        case .failure(let error):
            logger.error("\(EngineLog.sceneCannotLoad(self.surface, folder, error), privacy: .public)")
            return false
        }
    }

    // MARK: Running

    /// Starts drawing, from where scene time stopped. Nothing without a scene loaded.
    func start() {
        let run = shared.withLock { shared -> Int? in
            guard shared.drawing != nil else { return nil }
            shared.run += 1
            shared.running = true
            shared.clock.start()
            shared.startedAt = ContinuousClock.now
            shared.firstPictureDrawn = false
            return shared.run
        }
        guard let run else { return }
        soundtrack?.play()
        logger.notice("\(EngineLog.sceneDrawing(self.surface, from: self.shared.withLock(\.clock.latest)), privacy: .public)")
        let layer = LayerBox(layer: layer)
        let target = linkTarget
        SceneRenderThread.shared.perform { [self] in
            guard shared.withLock({ $0.run == run }) else { return }
            let link = CAMetalDisplayLink(metalLayer: layer.layer)
            link.delegate = target
            let rate = Float(LivepaperScene.framesPerSecond)
            link.preferredFrameRateRange = CAFrameRateRange(minimum: rate, maximum: rate, preferred: rate)
            link.preferredFrameLatency = 2
            // Checked and stored under one lock: a pause between the two would find no link to stop,
            // and the link stored after it would draw on. A later pause stops it on this thread, after this block.
            let (isCurrent, replaced) = shared.withLock { shared -> (Bool, LinkBox?) in
                guard shared.run == run else { return (false, nil) }
                defer { shared.link = LinkBox(link) }
                return (true, shared.link)
            }
            replaced?.link.invalidate()
            guard isCurrent else { return link.invalidate() }
            link.add(to: .current, forMode: .default)
        }
    }

    /// Stops drawing and scene time; the last picture stays on the layer.
    func pause(_ reason: String = "pause") {
        soundtrack?.pause()
        let link = shared.withLock { shared -> LinkBox? in
            shared.run += 1
            shared.running = false
            shared.clock.stop()
            defer { shared.link = nil }
            return shared.link
        }
        guard let link else { return }
        SceneRenderThread.shared.perform { link.link.invalidate() }
        logger.notice("\(EngineLog.sceneStopped(self.surface, at: self.shared.withLock(\.clock.latest), reason), privacy: .public)")
    }

    /// Stops drawing and lets the scene go, textures and all. `start` after `load` goes on from the same scene time.
    /// `reason` is the log's: a suspend, or a surface that holds a still of the scene (`still`).
    func suspend(_ reason: String = "suspend") {
        pause(reason)
        soundtrack?.stop()
        soundtrack = nil
        shared.withLock { shared in
            shared.drawing = nil
            shared.loads += 1
        }
    }

    /// Stops drawing and forgets the scene and its time.
    func stop() {
        pause("stop")
        soundtrack?.stop()
        soundtrack = nil
        shared.withLock { shared in
            shared.drawing = nil
            shared.folder = nil
            shared.loads += 1
            shared.clock.reset()
        }
    }

    /// A new display link on the same scene: the recovery levels short of loading it again.
    func restart() {
        pause("restart")
        start()
    }

    /// The folder of the scene loaded, or last asked for.
    var folder: URL? { shared.withLock(\.folder) }

    /// The scene time of the latest picture: where a paused, suspended or stopped scene stands.
    var sceneTime: Double { shared.withLock(\.clock.latest) }

    /// Waits for the first picture of this run to be drawn, up to `timeout`.
    func waitForFirstPicture(timeout: Duration = .seconds(1)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !shared.withLock(\.firstPictureDrawn) {
            guard clock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(8))
        }
        return true
    }

    /// The pictures presented, the frames committed and the frames the link
    /// asked for over `window`, for the watchdog; and whether, at its end, the
    /// engine stood ready to draw (its link up, its render thread answering).
    func displayedPictures(over window: Duration) async -> PictureCount {
        let before = shared.withLock(\.tally)
        try? await Task.sleep(for: window)
        let after = shared.withLock(\.tally)
        let running = shared.withLock { $0.link != nil && $0.tally.isGPUKeepingUp }
        let ready = running ? await SceneRenderThread.shared.answers(within: .milliseconds(250)) : false
        return SceneTally.count(from: before, to: after, over: window, framesPerSecond: LivepaperScene.framesPerSecond, engineReady: ready)
    }

    // MARK: On the render thread

    private struct Frame {
        var drawing: DrawingBox
        var time: Double
        var resize: SIMD2<Int>?
    }

    fileprivate func draw(_ update: CAMetalDisplayLink.Update, from link: CAMetalDisplayLink) {
        let texture = update.drawable.texture
        let size = SIMD2(texture.width, texture.height)
        let frame = shared.withLock { shared -> Frame? in
            guard shared.link?.link === link else { return nil }
            shared.tally.asked += 1
            guard let drawing = shared.drawing else { return nil }
            let resize = shared.drawnSize == size ? nil : size
            shared.drawnSize = size
            return Frame(drawing: drawing, time: shared.clock.time(forFrameAt: update.targetPresentationTimestamp), resize: resize)
        }
        guard let frame, let buffer = SceneGPU.shared?.queue.makeCommandBuffer() else { return }
        if let resize = frame.resize { frame.drawing.drawing.resize(width: resize.x, height: resize.y) }
        if let position = pointer?() { frame.drawing.drawing.pointerMoved(to: position) }
        buffer.label = "livepaper.scene"
        frame.drawing.drawing.draw(into: texture, on: buffer, at: frame.time)
        update.drawable.addPresentedHandler { [weak self] drawable in
            guard drawable.presentedTime > 0 else { return }
            self?.shared.withLock { $0.tally.presented += 1 }
        }
        buffer.addCompletedHandler { [weak self] buffer in
            let completed = buffer.status == .completed
            self?.shared.withLock { shared in
                if completed { shared.tally.completed += 1 } else { shared.tally.failed += 1 }
            }
            if completed { self?.firstPictureDrawn() }
        }
        buffer.present(update.drawable)
        buffer.commit()
        shared.withLock { $0.tally.committed += 1 }
    }

    private func firstPictureDrawn() {
        let startedAt = shared.withLock { shared -> ContinuousClock.Instant? in
            guard !shared.firstPictureDrawn else { return nil }
            shared.firstPictureDrawn = true
            return shared.startedAt
        }
        guard let startedAt else { return }
        let took = (ContinuousClock.now - startedAt) / .milliseconds(1)
        logger.notice("\(EngineLog.sceneFirstPicture(self.surface, milliseconds: took), privacy: .public)")
    }
}

/// The display link's delegate, which must be an `NSObject`; it hands each frame to its engine.
private final class LinkTarget: NSObject, CAMetalDisplayLinkDelegate, @unchecked Sendable {
    weak var engine: SceneEngine?

    func metalDisplayLink(_ link: CAMetalDisplayLink, needsUpdate update: CAMetalDisplayLink.Update) {
        engine?.draw(update, from: link)
    }
}

/// A drawing, handed to the render thread and used there only, one call at a time (`SceneDrawing`),
/// and its sounds, handed to the engine's owner.
private final class DrawingBox: @unchecked Sendable {
    let drawing: any SceneDrawing
    let soundtrack: SceneSoundtrack?

    init(_ drawing: any SceneDrawing, soundtrack: SceneSoundtrack?) {
        self.drawing = drawing
        self.soundtrack = soundtrack
    }
}

/// What draws scenes, carried to the queue that loads one. A type is only ever read.
private struct DrawingType: @unchecked Sendable {
    let type: any SceneDrawing.Type
}

/// The Metal slot, carried to the render thread to make each run's link on. Only the link reads it there.
private struct LayerBox: @unchecked Sendable {
    let layer: CAMetalLayer
}

/// A display link, made, added and invalidated on the render thread only.
private final class LinkBox: @unchecked Sendable {
    let link: CAMetalDisplayLink

    init(_ link: CAMetalDisplayLink) {
        self.link = link
    }
}

private let sceneLoadQueue = DispatchQueue(label: "app.livepaper.playback.scene-load", qos: .userInitiated)
