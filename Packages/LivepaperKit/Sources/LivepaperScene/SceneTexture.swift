import Compression
import CoreGraphics
import Foundation
import ImageIO

/// A Wallpaper Engine texture (`.tex`), whole, as the format was learned
/// from the samples:
///
///     "TEXV0005" "TEXI0001"                        each tag 8 characters and a NUL
///       i32 format, u32 flags, i32 texture width, height, i32 image width, height, u32
///     "TEXB000n", n 1 to 4
///       i32 image count; n >= 3: i32 FreeImage format (-1 raw, 2 JPEG, 13 PNG); n >= 4: i32
///       per image: i32 mip count; per mip: i32 width, height,
///         n >= 2: i32 LZ4 flag, i32 decompressed size; i32 size, the bytes (LZ4 raw when flagged)
///     "TEXS000n", n 2 or 3, only when animated
///       i32 frame count; n >= 3: i32 frame width, height
///       per frame: i32 image, f32 seconds, f32 x, y, then the frame's two axes (f32 x, y each)
///
/// The texture may be larger than its image (padded to a power of two); the
/// shaders are told both sizes. `SpriteSheet` reads the same files, strictly,
/// for a GIF scene's frames.
public struct SceneTexture: Sendable {
    public enum Format: Int32, Sendable {
        case rgba8888 = 0
        case rg88 = 8
        case r8 = 9
    }

    public struct Mip: Sendable {
        public let width: Int
        public let height: Int
        let isCompressed: Bool
        let decompressedSize: Int
        let payload: Data
    }

    /// One picture of a sprite sheet: where it is in which image, and for how long it shows.
    public struct Frame: Equatable, Sendable {
        public var image: Int
        public var seconds: Float
        public var x: Float
        public var y: Float
        /// The frame's two axes in the image, in pixels: across, then down.
        public var across: SIMD2<Float>
        public var down: SIMD2<Float>
    }

    public let formatCode: Int32
    public let flags: UInt32
    public let textureWidth: Int
    public let textureHeight: Int
    public let imageWidth: Int
    public let imageHeight: Int
    public let freeImageFormat: Int32
    /// Per image, its mips, largest first.
    public let images: [[Mip]]
    public let frames: [Frame]

    public var format: Format? { Format(rawValue: formatCode) }
    // What the flags mean is inferred from the samples: 0x1 on the point-filtered GIF, 0x2 on nearly
    // everything that should not repeat, 0x20 on the one texture whose payload is an MP4.
    public var isPointFiltered: Bool { flags & 0x1 != 0 }
    public var clamps: Bool { flags & 0x2 != 0 }
    public var isVideo: Bool { flags & 0x20 != 0 }

    public init(data: Data) throws(SceneReadError) {
        do {
            var reader = ByteReader(data)
            guard try reader.tag().hasPrefix("TEXV"), try reader.tag().hasPrefix("TEXI") else { throw SceneReadError.malformedScene }
            formatCode = try reader.i32()
            flags = try reader.u32()
            textureWidth = try reader.int()
            textureHeight = try reader.int()
            imageWidth = try reader.int()
            imageHeight = try reader.int()
            _ = try reader.u32()
            let container = try reader.tag()
            guard container.hasPrefix("TEXB"), let version = Int(container.dropFirst(4)), (1...4).contains(version) else {
                throw SceneReadError.malformedScene
            }
            let imageCount = try reader.int()
            guard (0...64).contains(imageCount) else { throw SceneReadError.malformedScene }
            freeImageFormat = version >= 3 ? try reader.i32() : -1
            if version >= 4 { _ = try reader.i32() }
            var images: [[Mip]] = []
            for _ in 0..<imageCount {
                let mipCount = try reader.int()
                guard (0...32).contains(mipCount) else { throw SceneReadError.malformedScene }
                var mips: [Mip] = []
                for _ in 0..<mipCount {
                    let width = try reader.int()
                    let height = try reader.int()
                    let isCompressed = version >= 2 ? try reader.i32() != 0 : false
                    let decompressedSize = version >= 2 ? try reader.int() : 0
                    let payload = try reader.bytes(try reader.int())
                    mips.append(Mip(
                        width: width, height: height, isCompressed: isCompressed, decompressedSize: decompressedSize, payload: payload
                    ))
                }
                images.append(mips)
            }
            self.images = images
            frames = try Self.readFrames(&reader)
        } catch let error as SceneReadError {
            throw error
        } catch {
            throw .malformedScene
        }
    }

    private static func readFrames(_ reader: inout ByteReader) throws -> [Frame] {
        guard reader.remaining > 9, let sheet = try? reader.tag(), sheet.hasPrefix("TEXS"), let version = Int(sheet.dropFirst(4)) else {
            return []
        }
        let count = try reader.int()
        guard (0...100_000).contains(count) else { throw SceneReadError.malformedScene }
        // The frame size, which each frame's own axes give again.
        if version >= 3 { _ = try reader.bytes(8) }
        var frames: [Frame] = []
        for _ in 0..<count {
            let image = try reader.int()
            let seconds = try reader.f32()
            let x = try reader.f32()
            let y = try reader.f32()
            let across = SIMD2(try reader.f32(), try reader.f32())
            let down = SIMD2(try reader.f32(), try reader.f32())
            frames.append(Frame(image: image, seconds: seconds, x: x, y: y, across: across, down: down))
        }
        return frames
    }

    /// Pixels of one image's mip, decoded: straight-alpha RGBA8 for an image
    /// stored as a file, otherwise as stored (RGBA8, RG8 or R8).
    public struct Pixels: Sendable {
        public let width: Int
        public let height: Int
        public let bytesPerPixel: Int
        public let bytes: Data
    }

    public func pixels(image: Int = 0, mip: Int = 0) throws(SceneReadError) -> Pixels {
        guard images.indices.contains(image), images[image].indices.contains(mip), !isVideo else { throw .malformedScene }
        let stored = images[image][mip]
        let raw = stored.isCompressed ? try Self.decompressLZ4(stored.payload, to: stored.decompressedSize) : stored.payload
        if freeImageFormat != -1 { return try Self.decodeImage(raw) }
        guard let format else { throw .malformedScene }
        let bytesPerPixel = switch format {
        case .rgba8888: 4
        case .rg88: 2
        case .r8: 1
        }
        // The sides are checked before they are multiplied: two that a file makes up would overflow.
        guard Self.fitsATexture(stored.width, stored.height) else { throw .malformedScene }
        let expected = stored.width * stored.height * bytesPerPixel
        guard raw.count >= expected else { throw .malformedScene }
        return Pixels(width: stored.width, height: stored.height, bytesPerPixel: bytesPerPixel, bytes: Data(raw.prefix(expected)))
    }

    /// The largest side a Metal texture has on the Macs Livepaper runs on.
    static let largestSide = 16384

    /// Both sides at least a pixel, and no longer than a texture's.
    static func fitsATexture(_ width: Int, _ height: Int) -> Bool {
        (1...largestSide).contains(width) && (1...largestSide).contains(height)
    }

    /// The first image's payload when it is a video (`isVideo`), as its file's bytes.
    public var videoPayload: Data? {
        guard isVideo else { return nil }
        return images.first?.first?.payload
    }

    static func decompressLZ4(_ bytes: Data, to size: Int) throws(SceneReadError) -> Data {
        guard size > 0, size <= 1 << 30, !bytes.isEmpty else { throw .malformedScene }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { destination in
            bytes.withUnsafeBytes { source -> Int in
                guard let to = destination.baseAddress, let from = source.baseAddress else { return 0 }
                return compression_decode_buffer(
                    to.assumingMemoryBound(to: UInt8.self), size, from.assumingMemoryBound(to: UInt8.self), bytes.count, nil,
                    COMPRESSION_LZ4_RAW
                )
            }
        }
        guard written == size else { throw .malformedScene }
        return output
    }

    /// A PNG or JPEG to straight-alpha RGBA8, which is what the shaders expect of a texture.
    static func decodeImage(_ data: Data) throws(SceneReadError) -> Pixels {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
            let space = CGColorSpace(name: CGColorSpace.sRGB)
        else { throw .malformedScene }
        let (width, height) = (image.width, image.height)
        // A file says what size it is, and could say one past all memory.
        guard fitsATexture(width, height) else { throw .malformedScene }
        var bytes = Data(count: width * height * 4)
        let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            // CoreGraphics draws premultiplied; undo it.
            guard ![.none, .noneSkipLast, .noneSkipFirst].contains(image.alphaInfo) else { return true }
            let pixels = buffer.bindMemory(to: UInt8.self)
            for index in stride(from: 0, to: width * height * 4, by: 4) {
                let alpha = Int(pixels[index + 3])
                guard alpha != 0, alpha != 255 else { continue }
                for channel in 0..<3 { pixels[index + channel] = UInt8(min(255, Int(pixels[index + channel]) * 255 / alpha)) }
            }
            return true
        }
        guard drawn else { throw .malformedScene }
        return Pixels(width: width, height: height, bytesPerPixel: 4, bytes: bytes)
    }
}
