import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import LivepaperCore
import UniformTypeIdentifiers

public enum ArtefactError: Error, Equatable, Sendable {
    case noPicture
    case posterNotWritten
}

/// Writes the poster: the first frame that is not black, at the picture's own
/// size. A video that fades in from black would otherwise sit in the library,
/// and on the desktop when playback is stopped, as a black tile.
@concurrent
func makePoster(of optimisedCopy: URL, at destination: URL) async throws {
    let asset = AVURLAsset(url: optimisedCopy)
    let duration = try await asset.load(.duration).seconds
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero

    // Looked for a quarter of a second at a time, and not for ever: a video that is dark throughout keeps its first frame.
    let times = stride(from: 0, to: min(duration, 20), by: 0.25).map { CMTime(seconds: $0, preferredTimescale: 600) }
    var first: CGImage?
    var poster: CGImage?
    for time in times {
        try Task.checkCancellation()
        guard let image = try? await generator.image(at: time).image else { continue }
        first = first ?? image
        if !image.isBlack {
            poster = image
            break
        }
    }

    guard let image = poster ?? first else { throw ArtefactError.noPicture }
    try writePoster(image, to: destination)
}

/// Writes a scene's poster when the scene cannot be drawn for one
/// (`ScenePoster`): the first picture of the item's preview, a still or a GIF,
/// cut about its middle to the scene's shape. A Workshop preview is square, and
/// a poster that is not the scene's shape would not line up with it on the
/// desktop or in the inspector.
func makeScenePoster(from preview: URL?, shape: Size, at destination: URL) throws {
    guard
        let preview,
        let source = CGImageSourceCreateWithURL(preview as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
        let cut = image.cropping(to: middle(of: image, shaped: shape))
    else { throw ArtefactError.noPicture }
    try writePoster(cut, to: destination)
}

/// The largest part of the image, about its middle, of the given shape.
func middle(of image: CGImage, shaped shape: Size) -> CGRect {
    let (width, height) = (Double(image.width), Double(image.height))
    let aspect = shape.width > 0 && shape.height > 0 ? shape.width / shape.height : width / max(height, 1)
    let size = width / height > aspect
        ? CGSize(width: (height * aspect).rounded(), height: height)
        : CGSize(width: width, height: (width / aspect).rounded())
    let origin = CGPoint(x: ((width - size.width) / 2).rounded(.down), y: ((height - size.height) / 2).rounded(.down))
    return CGRect(origin: origin, size: size)
}

private func writePoster(_ image: CGImage, to destination: URL) throws {
    guard let file = CGImageDestinationCreateWithURL(destination as CFURL, UTType.heic.identifier as CFString, 1, nil) else {
        throw ArtefactError.posterNotWritten
    }
    CGImageDestinationAddImage(file, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
    guard CGImageDestinationFinalize(file) else { throw ArtefactError.posterNotWritten }
}

extension CGImage {
    /// Black, or as good as: nothing in the picture, scaled down to a few hundred pixels, is brighter than a dark grey.
    var isBlack: Bool {
        let (width, height) = (32, 18)
        var pixels = [UInt8](repeating: 0, count: width * height)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
            ) else { return false }
            context.interpolationQuality = .low
            context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        return drawn && (pixels.max() ?? 0) < 32
    }
}
