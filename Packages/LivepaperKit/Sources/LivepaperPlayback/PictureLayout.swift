import AVFoundation
import CoreGraphics
import LivepaperCore

/// Core's rectangles grow downwards, as the picture does; Core Animation's and Core Graphics'
/// grow upwards on macOS. This is the one place that turns one into the other.
func flipped(_ rect: Rect, within height: Double) -> CGRect {
    CGRect(x: rect.origin.x, y: height - rect.maxY, width: rect.size.width, height: rect.size.height)
}

/// Where a layer showing a picture of `source` pixels goes on a surface, in the surface's
/// points, by Core's `pictureRect` on the surface's pixels. The still and the video are both
/// laid out here, so they line up. A picture of unknown size covers the surface.
func layerFrame(presentation: Presentation, source: Size?, surface: SurfaceGeometry) -> CGRect {
    let pixels = surface.pixelSize
    let picture = source.map { pictureRect(for: presentation, source: $0, surface: pixels) }
        ?? Rect(origin: Point(x: 0, y: 0), size: pixels)
    let scale = surface.scale > 0 ? surface.scale : 1
    let points = Rect(
        origin: Point(x: picture.origin.x / scale, y: picture.origin.y / scale),
        size: Size(width: picture.size.width / scale, height: picture.size.height / scale)
    )
    return flipped(points, within: surface.size.height)
}

/// Waits until `layer` has a picture, and says whether it got one before `timeout`.
///
/// A fade has to start when the incoming layer is ready for display, not when its first frame
/// is enqueued: decoding that frame takes some tens of milliseconds.
/// `isReadyForDisplay` is not key-value observable, so this is a short poll, bounded, as the
/// spike's was. It runs for the milliseconds a start takes and then stops.
///
/// Main thread only: AVFoundation isolates the layer to the main actor.
func waitUntilReadyForDisplay(_ layer: AVSampleBufferDisplayLayer, timeout: Duration = .seconds(1)) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while !onMainThread(layer, { $0.isReadyForDisplay }) {
        guard clock.now < deadline else { return false }
        try? await Task.sleep(for: .milliseconds(4))
    }
    return true
}

/// Runs `body` on a video layer from code that is on the main thread but not marked so.
///
/// AVFoundation isolates `AVSampleBufferDisplayLayer` to the main actor. The layer tree of a
/// surface lives on its owner's actor, which in the extension is the main actor, and is not
/// marked `@MainActor` itself so that the supervisor's code can drive it through
/// `SurfacePlayback`. This traps anywhere but the main thread.
func onMainThread<Value: Sendable>(
    _ layer: AVSampleBufferDisplayLayer,
    _ body: @MainActor (AVSampleBufferDisplayLayer) -> Value
) -> Value {
    let layer = MainThreadLayer(layer: layer)
    return MainActor.assumeIsolated { body(layer.layer) }
}

/// `@unchecked Sendable` only to reach `MainActor.assumeIsolated`, which traps unless this is
/// the main thread, where the layer belongs: it never crosses a thread.
private struct MainThreadLayer: @unchecked Sendable {
    let layer: AVSampleBufferDisplayLayer
}
