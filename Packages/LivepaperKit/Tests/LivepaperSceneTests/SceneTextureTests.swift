import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import LivepaperScene
import LivepaperTestSupport

/// Wallpaper Engine's textures and puppets, read whole for drawing, on files made from nothing.
struct SceneTextureTests {
    static func raw(width: Int, height: Int, bytesPerPixel: Int, value: UInt8) -> SyntheticScene.RawImage {
        SyntheticScene.RawImage(width: width, height: height, pixels: Data(repeating: value, count: width * height * bytesPerPixel))
    }

    static let formats: [Row<Int32, Int>] = [
        Row("RGBA8888 has four bytes a pixel", 0, 4),
        Row("RG88, a normal map, has two", 8, 2),
        Row("R8, a mask, has one", 9, 1),
    ]

    @Test(arguments: formats)
    func `reads raw pixels in each format the samples use, compressed or not`(row: Row<Int32, Int>) throws {
        for compressed in [false, true] {
            let data = SyntheticScene.texture(
                [Self.raw(width: 16, height: 8, bytesPerPixel: row.expected, value: 77)], frames: nil, compressed: compressed,
                format: row.input
            )

            let pixels = try SceneTexture(data: data).pixels()

            #expect(pixels.width == 16)
            #expect(pixels.height == 8)
            #expect(pixels.bytesPerPixel == row.expected)
            #expect(pixels.bytes == Data(repeating: 77, count: 16 * 8 * row.expected))
        }
    }

    @Test func `reads a sprite sheet's frames over two images, with their times and places`() throws {
        let colours = (0..<5).map { SyntheticScene.Colour(UInt8(50 * $0), 0, 0) }

        let texture = try SceneTexture(data: SyntheticScene.spriteSheet(colours, tile: (4, 2), perImage: 3, seconds: 0.25))

        #expect(texture.images.count == 2)
        #expect(texture.frames.map(\.image) == [0, 0, 0, 1, 1])
        #expect(texture.frames.map(\.x) == [0, 4, 8, 0, 4])
        #expect(texture.frames.allSatisfy { $0.seconds == 0.25 && $0.across == SIMD2(4, 0) && $0.down == SIMD2(0, 2) })
    }

    @Test func `decodes an image stored as a PNG to straight RGBA`() throws {
        let png = try Self.png(width: 3, height: 2, rgba: [10, 20, 30, 255])
        var data = SyntheticScene.texture([Self.raw(width: 3, height: 2, bytesPerPixel: 4, value: 0)], frames: nil, compressed: false)
        data = Self.storingFile(png, in: data)

        let pixels = try SceneTexture(data: data).pixels()

        #expect(pixels.width == 3)
        #expect(pixels.height == 2)
        #expect(Array(pixels.bytes.prefix(4)) == [10, 20, 30, 255])
    }

    @Test func `tells a texture whose payload is a video, and does not decode it as pixels`() throws {
        var data = SyntheticScene.texture([Self.raw(width: 2, height: 2, bytesPerPixel: 4, value: 1)], frames: nil, compressed: false)
        // The flags word follows the two tags and the format.
        data[data.startIndex + 22] |= 0x20

        let texture = try SceneTexture(data: data)

        #expect(texture.isVideo)
        #expect(texture.videoPayload != nil)
        #expect(throws: SceneReadError.malformedScene) { try texture.pixels() }
    }

    @Test func `refuses a file cut short, and one that is not a texture`() throws {
        let whole = SyntheticScene.texture([Self.raw(width: 4, height: 4, bytesPerPixel: 4, value: 9)], frames: nil, compressed: false)

        #expect(throws: SceneReadError.malformedScene) { try SceneTexture(data: whole.prefix(whole.count - 10)) }
        #expect(throws: SceneReadError.malformedScene) { try SceneTexture(data: Data("PKGV0018 not a texture".utf8)) }
    }

    // MARK: Puppets

    @Test func `reads a puppet's mesh, bone and animation`() throws {
        let puppet = try ScenePuppet(data: SyntheticScene.puppet(half: 10, frames: 4, step: 2))

        #expect(puppet.material == "materials/puppet.json")
        #expect(puppet.vertices.count == 4)
        #expect(puppet.vertices.map(\.position.x) == [-10, 10, 10, -10])
        #expect(puppet.vertices.allSatisfy { $0.weights == SIMD4(1, 0, 0, 0) })
        #expect(puppet.indices == [0, 1, 2, 0, 2, 3])
        #expect(puppet.bones.count == 1)
        #expect(puppet.bones[0].parent == -1)
        let animation = try #require(puppet.animations.first)
        #expect(animation.name == "sway")
        #expect(animation.framesPerSecond == 10)
        #expect(animation.tracks.first?.map(\.position.x) == [0, 2, 4, 6])
    }

    @Test func `refuses a puppet whose indices point past its vertices`() throws {
        var data = SyntheticScene.puppet(half: 10, frames: 2, step: 1)
        // The first index, just after the vertex block and the index block's length.
        let firstIndex = try #require(data.firstRange(of: Data([0, 0, 1, 0, 2, 0, 0, 0, 2, 0, 3, 0])))
        data[firstIndex.lowerBound] = 40

        #expect(throws: SceneReadError.malformedScene) { try ScenePuppet(data: data) }
    }

    // MARK: Helpers

    static func png(width: Int, height: Int, rgba: [UInt8]) throws -> Data {
        let pixels = Array((0..<width * height).map { _ in rgba }.joined())
        let provider = try #require(CGDataProvider(data: Data(pixels) as CFData))
        let image = try #require(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
        return data as Data
    }

    /// The texture with its one image stored as `file`, FreeImage's PNG (13), in place of its raw pixels.
    static func storingFile(_ file: Data, in texture: Data) -> Data {
        var data = texture
        // After "TEXB0003" and the image count comes the FreeImage format, then the one mip.
        let container = data.firstRange(of: Data("TEXB0003".utf8))!.upperBound + 1
        let formatAt = container + 4
        data.replaceSubrange(formatAt..<formatAt + 4, with: withUnsafeBytes(of: Int32(13).littleEndian) { Data($0) })
        let mipAt = formatAt + 4
        // mip count, width, height, compressed, decompressed size, size, bytes
        let sizeAt = mipAt + 20
        var rebuilt = data.prefix(sizeAt)
        rebuilt.append(withUnsafeBytes(of: Int32(file.count).littleEndian) { Data($0) })
        rebuilt.append(file)
        return rebuilt
    }
}
