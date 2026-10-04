import CoreGraphics
import Dispatch
import Foundation
import ImageIO
import IOSurface
import LivepaperCore
import Testing
@testable import LivepaperPlayback

struct PosterReadingTests {
    @Test func `poster work runs on a queue of its own, not on Swift's cooperative pool`() async {
        let label = await onPosterQueue { String(cString: __dispatch_queue_get_label(nil)) }

        #expect(label == "app.livepaper.playback.poster")
    }

    @Test func `a poster is read and decoded`() async throws {
        let url = try writePoster(width: 8, height: 6)
        defer { try? FileManager.default.removeItem(at: url) }

        let image = try #require(await loadPoster(url))

        #expect(image.width == 8)
        #expect(image.height == 6)
    }

    @Test func `a poster that cannot be read is nil`() async {
        let url = FileManager.default.temporaryDirectory.appending(path: "no-such-poster-\(UUID().uuidString).png")

        #expect(await loadPoster(url) == nil)
    }

    @Test func `the neutral colour fills the surface`() async throws {
        let surface = try #require(await renderColour(SurfaceLayers.neutralColour, surface: Size(width: 4, height: 2)))

        #expect(IOSurfaceGetWidth(surface) == 4)
        #expect(IOSurfaceGetHeight(surface) == 2)
    }
}

/// A PNG of one colour in the temporary folder.
private func writePoster(width: Int, height: Int) throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(path: "poster-\(UUID().uuidString).png")
    let context = try #require(CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ))
    context.setFillColor(CGColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    let image = try #require(context.makeImage())
    let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
    CGImageDestinationAddImage(destination, image, nil)
    #expect(CGImageDestinationFinalize(destination))
    return url
}
