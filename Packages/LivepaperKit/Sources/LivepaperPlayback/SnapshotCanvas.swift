import CoreGraphics
import CoreVideo
import IOSurface
import LivepaperCore
import VideoToolbox

/// Where the picture goes in a snapshot: the surface's size and the picture's rectangle, both
/// in pixels, the rectangle from Core's `pictureRect` (y grows downwards).
public struct SnapshotLayout: Equatable, Sendable {
    public var surface: Size
    public var picture: Rect

    public init(surface: Size, picture: Rect) {
        self.surface = surface
        self.picture = picture
    }
}

/// Where a snapshot's picture comes from.
enum SnapshotSource: Equatable, Sendable {
    /// The picture on this video layer, while it has one.
    case video(VideoSlot)
    /// The wallpaper's poster, laid out as the still is.
    case poster
    /// What the surface shows behind a wallpaper whose poster cannot be read.
    case neutralColour
}

/// Where a snapshot's picture comes from, best first: the picture of the video in front;
/// while its layer has none yet (just after acquire the first video is still starting, over no
/// still), the poster, as the surface shows a wallpaper without its video; the neutral colour
/// when the poster cannot be read. Nothing at all only with no wallpaper.
func snapshotSources(state: SurfacePlaybackState, hasWallpaper: Bool, front: VideoSlot?) -> [SnapshotSource] {
    guard hasWallpaper else { return [] }
    let video: [SnapshotSource] = switch state {
    case .playing, .paused, .suspended: front.map { [.video($0)] } ?? []
    case .nothing, .still: []
    }
    return video + [.poster, .neutralColour]
}

/// The picture WallpaperAgent shows while no live context is hosted (by construction):
/// what is on screen, cropped as the layer shows it, at the surface's pixel size, in BGRA.
enum SnapshotCanvas {
    /// The decoder's pictures are in a compressed pixel format that cannot be read directly,
    /// so the picture goes through a BGRA buffer first.
    static func image(of picture: CVPixelBuffer) -> CGImage? {
        var session: VTPixelTransferSession?
        VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &session)
        guard let session else { return nil }
        defer { VTPixelTransferSessionInvalidate(session) }
        guard let bgra = makeBuffer(width: CVPixelBufferGetWidth(picture), height: CVPixelBufferGetHeight(picture)),
              VTPixelTransferSessionTransferImage(session, from: picture, to: bgra) == noErr else { return nil }
        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(bgra, options: nil, imageOut: &image)
        return image
    }

    /// `image` drawn where the layer shows it, over black, as Fit's bars are.
    static func render(_ image: CGImage, _ layout: SnapshotLayout) -> IOSurface? {
        draw(on: layout.surface) { context, bounds in
            context.setFillColor(CGColor(gray: 0, alpha: 1))
            context.fill(bounds)
            context.interpolationQuality = .high
            context.draw(image, in: flipped(layout.picture, within: bounds.height))
        }
    }

    /// The whole surface in one colour.
    static func fill(_ colour: CGColor, surface: Size) -> IOSurface? {
        draw(on: surface) { context, bounds in
            context.setFillColor(colour)
            context.fill(bounds)
        }
    }

    private static func draw(on surface: Size, _ body: (CGContext, CGRect) -> Void) -> IOSurface? {
        let width = Int(surface.width.rounded())
        let height = Int(surface.height.rounded())
        guard width > 0, height > 0, let buffer = makeBuffer(width: width, height: height),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        body(context, CGRect(x: 0, y: 0, width: width, height: height))
        return CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue()
    }

    private static func makeBuffer(width: Int, height: Int) -> CVPixelBuffer? {
        let attributes = [kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary] as CFDictionary
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, attributes, &buffer)
        return buffer
    }
}
