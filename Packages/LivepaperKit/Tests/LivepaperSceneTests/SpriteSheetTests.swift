import CoreGraphics
import Foundation
import Testing
import LivepaperScene
import LivepaperTestSupport

struct SpriteSheetTests {
    static let colours = (0..<6).map { SyntheticScene.Colour(UInt8(40 * $0), UInt8(200 - 30 * $0), 90) }

    /// The colour of the middle pixel of a frame's picture.
    static func colour(of image: CGImage) -> SyntheticScene.Colour? {
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            let (width, height) = (Double(image.width), Double(image.height))
            context.draw(image, in: CGRect(x: -width / 2 + 0.5, y: -height / 2 + 0.5, width: width, height: height))
            return true
        }
        return drawn ? SyntheticScene.Colour(pixel[0], pixel[1], pixel[2]) : nil
    }

    @Test(arguments: [true, false])
    func `cuts its frames out of the images in order, over several images, compressed or not`(compressed: Bool) throws {
        let texture = SyntheticScene.spriteSheet(Self.colours, tile: (8, 6), perImage: 4, seconds: 0.1, compressed: compressed)

        let sheet = try SpriteSheet(texture: texture)

        #expect(sheet.images.map { [$0.width, $0.height] } == [[32, 6], [16, 6]])
        #expect(sheet.frames.map(\.image) == [0, 0, 0, 0, 1, 1])
        #expect(sheet.frames.map(\.rect) == [0, 8, 16, 24, 0, 8].map { CGRect(x: $0, y: 0, width: 8, height: 6) })
        #expect(sheet.frames.allSatisfy { abs($0.duration - 0.1) < 1e-6 })
        let pictures = try sheet.frames.map { try #require(sheet.image(of: $0)) }
        #expect(pictures.map { [$0.width, $0.height] } == Array(repeating: [8, 6], count: 6))
        #expect(pictures.map(Self.colour) == Self.colours)
    }

    @Test func `a frame's time is kept as the texture gives it`() throws {
        let image = SyntheticScene.RawImage(width: 4, height: 2, pixels: Data(repeating: 255, count: 32))
        let frames = [
            SyntheticScene.Frame(image: 0, seconds: 0.05, x: 0, y: 0, width: 2, height: 2),
            SyntheticScene.Frame(image: 0, seconds: 0.25, x: 2, y: 0, width: 2, height: 2),
        ]

        let sheet = try SpriteSheet(texture: SyntheticScene.texture([image], frames: frames))

        #expect(sheet.frames.map { ($0.duration * 1000).rounded() } == [50, 250])
    }

    static let unsupported: [Row<Data, SpriteSheetError>] = {
        let image = SyntheticScene.RawImage(width: 4, height: 2, pixels: Data(repeating: 255, count: 32))
        func frame(_ x: Float, seconds: Float = 0.1, image: Int = 0) -> SyntheticScene.Frame {
            SyntheticScene.Frame(image: image, seconds: seconds, x: x, y: 0, width: 2, height: 2)
        }
        return [
            Row("a still texture, with no sprite sheet", SyntheticScene.texture([image], frames: nil), .unsupported("no sprite sheet")),
            Row("a sheet of one frame", SyntheticScene.texture([image], frames: [frame(0)]), .unsupported("a single frame")),
            Row("a frame shown for no time", SyntheticScene.texture([image], frames: [frame(0), frame(2, seconds: 0)]),
                .unsupported("a frame with no time")),
            Row("a frame outside its image", SyntheticScene.texture([image], frames: [frame(0), frame(3)]),
                .unsupported("a frame outside its image")),
            Row("a frame from an image that is not there", SyntheticScene.texture([image], frames: [frame(0), frame(2, image: 1)]),
                .unreadable),
            Row("a block-compressed format", SyntheticScene.texture([image], frames: [frame(0), frame(2)], format: 7),
                .unsupported("texture format 7")),
            Row("cut short", SyntheticScene.texture([image], frames: [frame(0), frame(2)]).dropLast(5), .unreadable),
            Row("not a texture", Data("TEXQ".utf8), .unreadable),
        ]
    }()

    @Test(arguments: unsupported)
    func `a texture it cannot cut up says why`(row: Row<Data, SpriteSheetError>) {
        #expect(throws: row.expected) { try SpriteSheet(texture: row.input) }
    }
}
