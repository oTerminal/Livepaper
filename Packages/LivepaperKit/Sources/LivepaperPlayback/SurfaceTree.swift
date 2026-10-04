// A layer tree made whole before the agent hosts it, with two video layers up front, follows the
// spike's SurfaceLayers and Phosphene's finding that a layer added to a hosted context does not
// composite (MIT, (c) 2026 kageroumado, https://github.com/kageroumado/phosphene). See NOTICE at the
// repository root.

import AVFoundation
import CoreGraphics
import ImageIO
import LivepaperCore
import LivepaperScene
import QuartzCore

/// Where a picture goes: how it is fitted, and its size in pixels once known.
struct PicturePlacement: Equatable {
    var presentation: Presentation
    var size: Size?
}

/// The layers of one surface, and what is done to them, without the engines that play on them.
///
///     root     black behind a wallpaper, which is Fit's bars; the neutral colour with none
///     ├── still    the poster, laid out as its video would be
///     ├── lower    video, opaque once it has played
///     ├── upper    video, the only layer whose opacity is ever animated
///     └── scene    the Metal slot, where a scene is drawn over its poster
///
/// Changes go in a transaction without implicit animations and are pushed to the render server
/// at once: the tree lives in a remote context.
final class SurfaceTree {
    private static let barColour = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    private static let fadeKey = "livepaper.crossfade"
    /// Metal's limit for a texture's side; a picture zoomed past it is drawn smaller and scaled up.
    private static let largestDrawable = 16_384.0

    let root = CALayer()
    private let still = CALayer()
    private let video: VideoSlots<AVSampleBufferDisplayLayer>
    let feeds: VideoSlots<VideoLayerFeed>
    /// The Metal slot. Made here with the rest of the tree, since a layer added after the agent
    /// hosts the context does not composite, and shown only by its opacity, which the spike found is
    /// enough for a `CAMetalLayer` to draw on the desktop. Its device
    /// is set by the scene engine when it first draws, so a surface that only ever plays video
    /// never touches Metal.
    let scene = CAMetalLayer()

    init(prepareVideoLayer: @MainActor (AVSampleBufferDisplayLayer) -> Void) {
        let lower = AVSampleBufferDisplayLayer()
        let upper = AVSampleBufferDisplayLayer()
        video = VideoSlots(lower: lower, upper: upper)
        feeds = VideoSlots(lower: Self.feed(for: lower, prepareVideoLayer), upper: Self.feed(for: upper, prepareVideoLayer))

        transaction {
            root.masksToBounds = true
            root.backgroundColor = SurfaceLayers.neutralColour
            still.contentsGravity = .resize
            still.opacity = 0
            root.addSublayer(still)
            for layer in video.all {
                layer.isOpaque = true
                layer.opacity = 0
                root.addSublayer(layer)
            }
            scene.pixelFormat = SceneFolder.pixelFormat
            scene.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
            scene.framebufferOnly = true
            scene.isOpaque = true
            scene.maximumDrawableCount = 3
            scene.allowsNextDrawableTimeout = true
            scene.presentsWithTransaction = false
            scene.opacity = 0
            root.addSublayer(scene)
        }
    }

    /// The Metal slot where `placement` puts the scene, and its drawables that size in pixels.
    func layOutScene(_ placement: PicturePlacement, on geometry: SurfaceGeometry) {
        let scale = geometry.scale > 0 ? geometry.scale : 1
        let rect = frame(for: placement, on: geometry)
        scene.frame = rect
        scene.contentsScale = scale
        let side = { (points: Double) in min(max(1, (points * scale).rounded()), Self.largestDrawable) }
        scene.drawableSize = CGSize(width: side(rect.width), height: side(rect.height))
    }

    func showScene(_ shown: Bool) {
        scene.opacity = shown ? 1 : 0
    }

    private static func feed(
        for layer: AVSampleBufferDisplayLayer,
        _ prepareVideoLayer: @MainActor (AVSampleBufferDisplayLayer) -> Void
    ) -> VideoLayerFeed {
        onMainThread(layer) { layer in
            // pictureRect gives the layer the picture's shape already, Stretch included.
            layer.videoGravity = .resize
            prepareVideoLayer(layer)
            return VideoLayerFeed(layer: layer)
        }
    }

    func transaction(_ changes: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        changes()
        CATransaction.commit()
        CATransaction.flush()
    }

    /// Every layer by Core's `pictureRect`, so that the still and the video line up.
    func layOut(_ geometry: SurfaceGeometry, still stillPlacement: PicturePlacement?, video placements: VideoSlots<PicturePlacement?>) {
        let scale = geometry.scale > 0 ? geometry.scale : 1
        root.frame = CGRect(x: 0, y: 0, width: geometry.size.width, height: geometry.size.height)
        root.contentsScale = scale
        still.frame = frame(for: stillPlacement, on: geometry)
        still.contentsScale = scale
        for slot in VideoSlot.allCases {
            video[slot].frame = frame(for: placements[slot], on: geometry)
            video[slot].contentsScale = scale
        }
    }

    private func frame(for placement: PicturePlacement?, on geometry: SurfaceGeometry) -> CGRect {
        layerFrame(presentation: placement?.presentation ?? Presentation(), source: placement?.size, surface: geometry)
    }

    /// Black behind a wallpaper, for Fit's bars; the neutral colour when there is none.
    func showBackground(behindWallpaper: Bool) {
        root.backgroundColor = behindWallpaper ? Self.barColour : SurfaceLayers.neutralColour
    }

    func showStill(_ image: CGImage?) {
        still.contents = image
        still.opacity = image == nil ? 0 : 1
    }

    func apply(_ changes: [OpacityChange]) {
        for change in changes {
            video[change.slot].removeAnimation(forKey: Self.fadeKey)
            video[change.slot].opacity = change.opacity
        }
    }

    /// An explicit animation runs in the render server, so it keeps going inside a remote
    /// context without this process driving each frame.
    func animate(_ change: OpacityChange, over duration: Duration) {
        let layer = video[change.slot]
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = layer.presentation()?.opacity ?? layer.opacity
        fade.toValue = change.opacity
        fade.duration = duration / .seconds(1)
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer.add(fade, forKey: Self.fadeKey)
        layer.opacity = change.opacity
    }

    func hideVideo() {
        apply(VideoSlot.allCases.map { OpacityChange($0, 0) })
    }

    /// Stops any fade under way where it is headed.
    func stopFades() {
        for layer in video.all { layer.removeAnimation(forKey: Self.fadeKey) }
    }

    /// Whether the layer got a picture before the bounded wait ran out.
    func waitUntilReady(_ slot: VideoSlot) async -> Bool {
        await waitUntilReadyForDisplay(video[slot])
    }
}

private let posterQueue = DispatchSerialQueue(label: "app.livepaper.playback.poster", qos: .userInitiated)

/// Runs the layer trees' own blocking work (reading and decoding a poster, drawing a snapshot)
/// on a queue of its own: never on the owner's actor, and never on Swift's cooperative pool,
/// which has a thread per core and none to spare for a file read.
func onPosterQueue<Value: Sendable>(_ work: @escaping @Sendable () -> Value) async -> Value {
    await withCheckedContinuation { continuation in
        posterQueue.async { continuation.resume(returning: work()) }
    }
}

/// Decoded at once rather than when first drawn.
func loadPoster(_ url: URL) async -> CGImage? {
    await onPosterQueue {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
    }
}

func renderPoster(_ image: CGImage, _ layout: SnapshotLayout) async -> IOSurface? {
    await onPosterQueue { SnapshotCanvas.render(image, layout) }
}

func renderColour(_ colour: CGColor, surface: Size) async -> IOSurface? {
    await onPosterQueue { SnapshotCanvas.fill(colour, surface: surface) }
}
