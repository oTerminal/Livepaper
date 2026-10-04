import CoreGraphics
import CoreMedia
import Foundation
import ImageIO
import Synchronization

/// How an engine stops advancing, and what it keeps. A pause keeps the decoder, as it keeps the
/// readers, so that resuming is instant: a covered display keeps its decoder. A suspend, a held
/// still and nothing at all give it back.
enum Halt: Sendable {
    case pause
    case suspend
    case stop

    struct Kept: Equatable, Sendable {
        var decoder: Bool
        /// The last picture stays on the layer.
        var picture: Bool
    }

    var keeps: Kept {
        switch self {
        case .pause: Kept(decoder: true, picture: true)
        case .suspend: Kept(decoder: false, picture: true)
        case .stop: Kept(decoder: false, picture: false)
        }
    }
}

/// The hardware decoder a layer's renderer holds, if any, and the format of the video it was
/// made for.
///
/// A renderer keeps the decoder session it made for a video, with its thread and its surfaces
/// in VTDecoderXPCService, for as long as the renderer lives: flushing it, stopping its
/// requests, taking it off its synchroniser, an end-of-media marker, an uncompressed frame, or
/// hiding its layer all leave the session where it is (measured on macOS 27). The layers are
/// never replaced, since a layer added to a hosted context does not composite, and a renderer
/// that has been pulled from outlives its layer anyway. What a renderer does let go of is a
/// decoder for another format: given a frame the hardware decoder does not take, it swaps the
/// hardware session for one that can decode that frame. So an engine that gives the decoder back
/// flushes and enqueues `releaseFrame(shapedLike:at:)`; the next start's first frame makes a
/// hardware session again.
///
/// Shared by the engines that drive one layer in turn, so that the one that stops gives back
/// what an earlier one left.
final class LayerDecoder: Sendable {
    private let video = Mutex<CMVideoFormatDescription?>(nil)

    /// A start put its first frame of `format` on the layer.
    func fed(_ format: CMFormatDescription?) {
        guard let format, format.mediaType == .video else { return }
        video.withLock { $0 = format }
    }

    /// The format of the video whose decoder the layer holds, once: nil when it holds none.
    func release() -> CMVideoFormatDescription? {
        video.withLock { $0.take() }
    }
}

/// A frame that makes a renderer give its hardware decoder back: a 16 × 16 JPEG, which the
/// renderer decodes and never shows, under a format description the size of `video` with its
/// clean aperture and pixel aspect ratio. The layer lays out the picture it keeps by the latest
/// format it was given, so a JPEG of its own small size would move that picture; the decoder
/// goes by the payload, so a large JPEG would only cost more.
func releaseFrame(shapedLike video: CMVideoFormatDescription, at time: CMTime) -> CMSampleBuffer? {
    guard let jpeg = ReleaseJPEG.bytes else { return nil }
    let size = video.dimensions
    let shape = [kCMFormatDescriptionExtension_CleanAperture, kCMFormatDescriptionExtension_PixelAspectRatio]
    var extensions: [CFString: Any] = [:]
    for key in shape {
        if let value = CMFormatDescriptionGetExtension(video, extensionKey: key) { extensions[key] = value }
    }
    var format: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreate(
        allocator: nil,
        codecType: kCMVideoCodecType_JPEG,
        width: size.width,
        height: size.height,
        extensions: extensions.isEmpty ? nil : extensions as CFDictionary,
        formatDescriptionOut: &format
    )
    guard let format,
          let data = try? CMBlockBuffer(length: jpeg.count),
          (try? jpeg.withUnsafeBytes { try data.replaceDataBytes(with: $0) }) != nil else { return nil }
    let timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: time, decodeTimeStamp: .invalid)
    guard let frame = try? CMSampleBuffer(
        dataBuffer: data,
        formatDescription: format,
        numSamples: 1,
        sampleTimings: [timing],
        sampleSizes: [jpeg.count]
    ) else { return nil }
    frame.doNotDisplay()
    return frame
}

private enum ReleaseJPEG {
    /// Black, made once with ImageIO.
    static let bytes: Data? = {
        let side = 16
        guard let context = CGContext(
            data: nil,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { return nil }
        context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: side, height: side))
        let data = NSMutableData()
        guard let image = context.makeImage(),
              let destination = CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }()
}
