import Compression
import CoreGraphics
import Foundation
import ImageIO

public enum SpriteSheetError: Error, Equatable, Sendable {
    /// Not a texture this reader knows, or one cut short.
    case unreadable
    /// A texture, but not one whose pictures can be taken out as they are:
    /// a block-compressed format, say, or no sprite sheet at all.
    case unsupported(String)
}

/// A Wallpaper Engine texture (`.tex`) that holds a sprite sheet: an animated
/// picture as frames cut from one or more larger images, each shown for its
/// own time. A GIF scene is one of these and nothing else.
///
///     "TEXV0005" "TEXI0001"                       each tag 8 characters and a NUL
///       i32 format (0 RGBA8888), i32 flags, i32 texture width, height, i32 image width, height, u32
///     "TEXB000n", n 1 to 4
///       i32 image count; n >= 3: i32 FreeImage format (-1 raw); n >= 4: i32
///       per image: i32 mip count; per mip: i32 width, height,
///         n >= 2: i32 LZ4 flag, i32 decompressed size; i32 size, the bytes (LZ4 raw when flagged)
///     "TEXS000n", n 2 or 3
///       i32 frame count; n >= 3: i32 frame width, height
///       per frame: i32 image, f32 seconds, f32 x, y, then the frame's two axes, (f32 width, f32 0) and (f32 0, f32 height)
///
/// Only the first mip of each image is read. Raw pictures must be RGBA8888;
/// an image stored as a file (PNG, JPEG) is decoded by ImageIO.
public struct SpriteSheet: @unchecked Sendable {
    public struct Frame: Equatable, Sendable {
        /// Which of `images` the frame is cut from.
        public var image: Int
        /// How long the frame is shown, in seconds.
        public var duration: Double
        /// Where the frame is in its image, in pixels, from the top left.
        public var rect: CGRect

        public init(image: Int, duration: Double, rect: CGRect) {
            self.image = image
            self.duration = duration
            self.rect = rect
        }
    }

    public let frames: [Frame]
    /// Decoded, and immutable: `CGImage` is safe to share, which is what makes this `Sendable`.
    public let images: [CGImage]

    /// Reads the texture and decodes its images. Throws `unsupported` for a
    /// texture that is readable but has no sprite sheet this can cut up.
    public init(texture data: Data) throws(SpriteSheetError) {
        var reader = ByteReader(data)
        do {
            let header = try TextureHeader(&reader)
            let images = try Self.readImages(&reader, header)
            let frames = try Self.readFrames(&reader)
            try Self.check(frames, against: images)
            self.images = images
            self.frames = frames
        } catch let error as SpriteSheetError {
            throw error
        } catch {
            throw .unreadable
        }
    }

    /// The frame's picture, cut from its image.
    public func image(of frame: Frame) -> CGImage? {
        images[frame.image].cropping(to: frame.rect.integral)
    }

    // MARK: Reading

    /// What the sections before the images say that the images need.
    private struct TextureHeader {
        var format: Int32
        /// Of the images' section, "TEXB000n".
        var version: Int
        /// -1 for raw pixels, otherwise the images are files.
        var fileFormat: Int32
        var imageCount: Int

        init(_ reader: inout ByteReader) throws {
            guard try reader.tag().hasPrefix("TEXV"), try reader.tag() == "TEXI0001" else { throw SpriteSheetError.unreadable }
            format = try reader.i32()
            // The flags (filtering and clamping, of no use to a video), the texture's and the
            // image's sizes (each mip says its own) and a word nobody has explained.
            _ = try reader.bytes(24)

            let container = try reader.tag()
            guard container.hasPrefix("TEXB"), let version = Int(container.dropFirst(4)), (1...4).contains(version) else {
                throw SpriteSheetError.unsupported(container)
            }
            self.version = version
            imageCount = Int(try reader.i32())
            fileFormat = version >= 3 ? try reader.i32() : -1
            if version >= 4 { _ = try reader.i32() }
            guard (1...64).contains(imageCount) else { throw SpriteSheetError.unreadable }
        }
    }

    private static func readImages(_ reader: inout ByteReader, _ header: TextureHeader) throws -> [CGImage] {
        var images: [CGImage] = []
        for _ in 0..<header.imageCount {
            let mips = Int(try reader.i32())
            guard mips >= 1 else { throw SpriteSheetError.unreadable }
            var first: CGImage?
            for mip in 0..<mips {
                let width = Int(try reader.i32())
                let height = Int(try reader.i32())
                let compressed = header.version >= 2 ? try reader.i32() != 0 : false
                let decompressedSize = header.version >= 2 ? Int(try reader.i32()) : 0
                let bytes = try reader.bytes(Int(try reader.i32()))
                // The smaller mips are skipped over, not decoded.
                guard mip == 0 else { continue }
                let payload = compressed ? try decompressLZ4(bytes, to: decompressedSize) : bytes
                first = try picture(payload, width: width, height: height, header)
            }
            guard let first else { throw SpriteSheetError.unreadable }
            images.append(first)
        }
        return images
    }

    private static func readFrames(_ reader: inout ByteReader) throws -> [Frame] {
        guard !reader.isAtEnd else { throw SpriteSheetError.unsupported("no sprite sheet") }
        let sheet = try reader.tag()
        guard sheet.hasPrefix("TEXS"), let version = Int(sheet.dropFirst(4)), (2...3).contains(version) else {
            throw SpriteSheetError.unsupported(sheet)
        }
        let count = Int(try reader.i32())
        // The frame size, which each frame's own axes give again.
        if version >= 3 { _ = try reader.bytes(8) }
        guard (1...100_000).contains(count) else { throw SpriteSheetError.unreadable }

        var frames: [Frame] = []
        for _ in 0..<count {
            let image = Int(try reader.i32())
            let seconds = Double(try reader.f32())
            let origin = CGPoint(x: Double(try reader.f32()), y: Double(try reader.f32()))
            let across = CGVector(dx: Double(try reader.f32()), dy: Double(try reader.f32()))
            let down = CGVector(dx: Double(try reader.f32()), dy: Double(try reader.f32()))
            // A frame turned in its image would need more than cutting out.
            guard across.dy == 0, down.dx == 0 else { throw SpriteSheetError.unsupported("a frame that is turned") }
            let size = CGSize(width: across.dx, height: down.dy)
            frames.append(Frame(image: image, duration: seconds, rect: CGRect(origin: origin, size: size)))
        }
        return frames
    }

    /// Every frame lies inside its image and is shown for some time, and the
    /// sheet has more than one: a still is no animation.
    private static func check(_ frames: [Frame], against images: [CGImage]) throws(SpriteSheetError) {
        guard frames.count > 1 else { throw .unsupported("a single frame") }
        for frame in frames {
            guard images.indices.contains(frame.image) else { throw .unreadable }
            guard frame.duration.isFinite, frame.duration > 0 else { throw .unsupported("a frame with no time") }
            let bounds = CGRect(x: 0, y: 0, width: images[frame.image].width, height: images[frame.image].height)
            guard frame.rect.width >= 1, frame.rect.height >= 1, bounds.insetBy(dx: -0.5, dy: -0.5).contains(frame.rect) else {
                throw .unsupported("a frame outside its image")
            }
        }
    }

    private static func decompressLZ4(_ bytes: Data, to size: Int) throws -> Data {
        guard size > 0, size <= 1 << 30, !bytes.isEmpty else { throw SpriteSheetError.unreadable }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { destination in
            bytes.withUnsafeBytes { source -> Int in
                guard let to = destination.baseAddress, let from = source.baseAddress else { return 0 }
                return compression_decode_buffer(
                    to.assumingMemoryBound(to: UInt8.self), size,
                    from.assumingMemoryBound(to: UInt8.self), bytes.count,
                    nil, COMPRESSION_LZ4_RAW
                )
            }
        }
        guard written == size else { throw SpriteSheetError.unreadable }
        return output
    }

    private static func picture(_ payload: Data, width: Int, height: Int, _ header: TextureHeader) throws -> CGImage {
        if header.fileFormat >= 0 {
            // The file's own size is read before it is decoded, since it could say one past all memory.
            guard
                let source = CGImageSourceCreateWithData(payload as CFData, nil),
                let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                let fileWidth = properties[kCGImagePropertyPixelWidth] as? Int,
                let fileHeight = properties[kCGImagePropertyPixelHeight] as? Int,
                SceneTexture.fitsATexture(fileWidth, fileHeight),
                let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
            else { throw SpriteSheetError.unreadable }
            return image
        }
        guard header.format == 0 else { throw SpriteSheetError.unsupported("texture format \(header.format)") }
        // The sides are checked before they are multiplied: two that a file makes up would overflow.
        guard SceneTexture.fitsATexture(width, height), payload.count == width * height * 4 else { throw SpriteSheetError.unreadable }
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let provider = CGDataProvider(data: payload as CFData),
            let image = CGImage(
                width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
            )
        else { throw SpriteSheetError.unreadable }
        return image
    }
}
