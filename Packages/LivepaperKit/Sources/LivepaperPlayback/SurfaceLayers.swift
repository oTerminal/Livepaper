// One layer tree per surface, made before the first reply, with switches and crossfades in place on
// two video layers, follows the spike's SurfaceLayers and Phosphene's finding that a layer added
// after the agent hosts the context does not composite (MIT, (c) 2026 kageroumado,
// https://github.com/kageroumado/phosphene). See NOTICE at the repository root.

import AVFoundation
import CoreGraphics
import LivepaperCore
import os
import QuartzCore

/// The layer tree of one surface and the engines on it.
///
/// The tree (`SurfaceTree`) is made whole in `init`, before the first reply to the agent: a
/// layer added after the agent hosts the context does not composite, so layers are never added
/// or replaced later, and switches and crossfades happen on the two video layers made up front.
///
/// Runs on its owner's actor, which in the extension is the main actor. It is not marked
/// `@MainActor` so that the supervisor's code can drive it through `SurfacePlayback`, but it
/// must stay on the main thread: AVFoundation isolates the video layers to the main actor, and
/// the few calls on them trap anywhere else.
///
/// A request that comes during a crossfade waits for it to end, and the last one wins. A video
/// that cannot be played holds its poster, and a poster that cannot be read shows the neutral colour.
/// Before a surface is let go, `showNothing()`: a renderer must not go while an engine still feeds it.
///
/// Recovery, inside the process:
/// - `.flush`: the engine in front flushes and starts again from a fresh reader.
/// - `.rebuildSurface`: new engines on the same two layers. The old ones are retired at once,
///   even if one is stuck, and never touch the layers again; each new one flushes its layer
///   before it enqueues. The video in front starts again on its layer, keeping its last picture
///   until the new first frame. The other layer keeps what its old engine left until a video
///   next starts on it, which clears it first (`CrossfadePlan.clears`).
/// - `.rebuildPipeline`: everything on the surface built again from the wallpaper: new engines,
///   the poster read again and held while the video starts, the layers laid out afresh.
public final class SurfaceLayers: SurfacePlayback {
    /// The crossfade between two wallpapers. The picture is content, not interface,
    /// so the 300 ms rule does not apply.
    public static let crossfadeDuration: Duration = .seconds(1)
    /// What a surface shows when there is nothing to show.
    public static let neutralColour = CGColor(srgbRed: 0.12, green: 0.12, blue: 0.12, alpha: 1)

    public let id: SurfaceID
    /// The layer the extension hands to the surface's remote context.
    public var root: CALayer { tree.root }
    public internal(set) var state = SurfacePlaybackState.nothing
    public internal(set) var wallpaper: SurfaceWallpaper?

    struct Showing: Equatable {
        var wallpaper: SurfaceWallpaper
        /// The video's size in pixels, once its engine has read it.
        var size: Size?
    }

    struct Poster {
        var image: CGImage
        var size: Size
        var presentation: Presentation

        init(_ image: CGImage, presentation: Presentation) {
            self.image = image
            size = Size(width: Double(image.width), height: Double(image.height))
            self.presentation = presentation
        }
    }

    let tree: SurfaceTree
    var engines: VideoSlots<LoopEngine>
    let logger: Logger
    var geometry: SurfaceGeometry
    /// The layer the video on screen is on.
    var front: VideoSlot?
    /// A layer whose engine is starting, or whose video is fading in.
    var incoming: VideoSlot?
    /// What each layer plays, or was last asked to.
    var showing = VideoSlots<Showing?>(lower: nil, upper: nil)
    var poster: Poster?
    /// The latest request that came during a crossfade, for when it ends.
    var queued: (wallpaper: SurfaceWallpaper, crossfade: Bool)?
    /// Changes when the surface is told to show something else altogether, so that a start or a
    /// crossfade under way finds out and leaves the layers alone.
    var epoch = 0
    var metricsProbe = false

    /// `prepareVideoLayer` is called on each video layer before anything else: the extension
    /// passes the bridge's `disallowDisplayCompositing` there, since this module never links the bridge.
    public init(
        id: SurfaceID,
        geometry: SurfaceGeometry,
        logger: Logger,
        prepareVideoLayer: @MainActor (AVSampleBufferDisplayLayer) -> Void
    ) {
        self.id = id
        self.geometry = geometry
        self.logger = logger
        tree = SurfaceTree(prepareVideoLayer: prepareVideoLayer)
        engines = VideoSlots(
            lower: LoopEngine(feed: tree.feeds.lower, logger: logger),
            upper: LoopEngine(feed: tree.feeds.upper, logger: logger)
        )
        tree.transaction { layOut() }
    }

    // MARK: SurfacePlayback

    public func show(_ wallpaper: SurfaceWallpaper, crossfade: Bool) async {
        self.wallpaper = wallpaper
        if let target = incoming ?? front, showing[target]?.wallpaper.video == wallpaper.video {
            // The same video: its presentation and volume change in place, and it goes on as it was.
            queued = nil
            showing[target]?.wallpaper = wallpaper
            tree.transaction { layOut() }
            await engines[target].setVolume(wallpaper.volume)
            return
        }

        let plan = planCrossfade(CrossfadeSituation(front: front, incoming: incoming), crossfade: crossfade)
        switch plan.start {
        case .afterCrossfade:
            queued = (wallpaper, crossfade)
        case .redirect(let slot), .inPlace(let slot):
            await switchInPlace(slot, to: wallpaper)
        case .fresh(let slot):
            await start(wallpaper, on: slot, plan)
        }
    }

    public func holdStill(poster wallpaper: SurfaceWallpaper) async {
        epoch += 1
        let run = epoch
        queued = nil
        self.wallpaper = wallpaper
        let image = await loadPoster(wallpaper.poster)
        guard run == epoch else { return }
        if image == nil { logger.error("\(EngineLog.posterUnreadable(self.id, wallpaper.poster), privacy: .public)") }

        poster = image.map { Poster($0, presentation: wallpaper.presentation) }
        state = .still
        front = nil
        incoming = nil
        showing = VideoSlots(lower: nil, upper: nil)
        tree.transaction {
            tree.showBackground(behindWallpaper: image != nil)
            tree.showStill(image)
            tree.hideVideo()
            layOut()
        }
        await stopEngines()
    }

    public func showNothing() async {
        epoch += 1
        queued = nil
        wallpaper = nil
        state = .nothing
        poster = nil
        front = nil
        incoming = nil
        showing = VideoSlots(lower: nil, upper: nil)
        tree.transaction {
            tree.showBackground(behindWallpaper: false)
            tree.showStill(nil)
            tree.hideVideo()
        }
        await stopEngines()
    }

    public func pause() async {
        guard state == .playing else { return }
        state = .paused
        for engine in activeEngines { await engine.pause() }
    }

    public func resume() async {
        guard state == .paused || state == .suspended else { return }
        state = .playing
        for engine in activeEngines { await engine.resume() }
    }

    public func suspend() async {
        guard state == .playing || state == .paused else { return }
        state = .suspended
        for engine in activeEngines { await engine.suspend() }
    }

    public func recover(_ level: RecoveryLevel) async {
        switch level {
        case .flush:
            guard let slot = front ?? incoming else { return }
            await engines[slot].restart()
        case .rebuildSurface:
            await rebuildSurface()
        case .rebuildPipeline:
            await rebuildPipeline()
        case .restartAgent:
            // The app's, never the surface's.
            return
        }
    }

    public func displayedPictures(over window: Duration) async -> PictureCount? {
        guard state == .playing, let slot = front ?? incoming else { return nil }
        return await engines[slot].displayedPictures(over: window)
    }

    public func layout(surface geometry: SurfaceGeometry) {
        self.geometry = geometry
        tree.transaction { layOut() }
    }

    // MARK: Outside the protocol

    /// What is on screen, for WallpaperAgent's snapshot: the video's picture, or the poster
    /// while the video has no picture on its layer yet, cropped as the layers show it, at the
    /// surface's pixel size, in BGRA. Nil only with no wallpaper.
    public func snapshotPicture() async -> IOSurface? {
        let pixels = geometry.pixelSize
        for source in snapshotSources(state: state, hasWallpaper: wallpaper != nil, front: front) {
            if let picture = await snapshot(from: source, pixels) { return picture }
        }
        return nil
    }

    /// Switches the engines' displayed-picture probe on or off. While it is on, each logs the
    /// metrics line for this surface every `LoopEngine.metricsInterval` loops.
    public func setMetricsProbe(_ on: Bool) async {
        metricsProbe = on
        await applyMetricsProbe()
    }

    // MARK: Helpers

    var activeEngines: [LoopEngine] {
        Set([front, incoming].compactMap(\.self)).map { engines[$0] }
    }

    func stopEngines() async {
        let lower = engines.lower
        let upper = engines.upper
        async let lowerStopped: Void = lower.stop()
        async let upperStopped: Void = upper.stop()
        _ = await (lowerStopped, upperStopped)
    }

    func applyMetricsProbe() async {
        let lower = engines.lower
        let upper = engines.upper
        await lower.setMetricsProbe(metricsProbe, subject: .surface(id))
        await upper.setMetricsProbe(metricsProbe, subject: .surface(id))
    }

    /// Call inside a transaction.
    func layOut() {
        tree.layOut(
            geometry,
            still: poster.map { PicturePlacement(presentation: $0.presentation, size: $0.size) },
            video: VideoSlots(
                lower: showing.lower.map { PicturePlacement(presentation: $0.wallpaper.presentation, size: $0.size) },
                upper: showing.upper.map { PicturePlacement(presentation: $0.wallpaper.presentation, size: $0.size) }
            )
        )
    }

    private func snapshot(from source: SnapshotSource, _ pixels: Size) async -> IOSurface? {
        switch source {
        case .video(let slot):
            guard let current = showing[slot], let size = current.size else { return nil }
            let picture = pictureRect(for: current.wallpaper.presentation, source: size, surface: pixels)
            return await engines[slot].snapshot(SnapshotLayout(surface: pixels, picture: picture))
        case .poster:
            // The still that is held, or else the wallpaper's poster read for the purpose.
            guard let poster = await snapshotPoster() else { return nil }
            let picture = pictureRect(for: poster.presentation, source: poster.size, surface: pixels)
            return await renderPoster(poster.image, SnapshotLayout(surface: pixels, picture: picture))
        case .neutralColour:
            return await renderColour(Self.neutralColour, surface: pixels)
        }
    }

    private func snapshotPoster() async -> Poster? {
        if let poster { return poster }
        guard let wallpaper, let image = await loadPoster(wallpaper.poster) else { return nil }
        return Poster(image, presentation: wallpaper.presentation)
    }

    /// The poster under a video that is now opaque over it is let go.
    func releaseStill() {
        guard poster != nil else { return }
        poster = nil
        tree.transaction { tree.showStill(nil) }
    }
}
