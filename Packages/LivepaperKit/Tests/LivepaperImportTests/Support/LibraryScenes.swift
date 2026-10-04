import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import LivepaperCore
import LivepaperImport
import LivepaperScene
import LivepaperTestSupport

/// Wallpapers already in the bench's library, as a launch finds them: for the work the app does
/// again at launch on scenes imported earlier (`ScenePreparation.refresh`, `ScenePoster.refresh`).
extension ImportBench {
    /// A scene wallpaper whose folder holds `entries` and, when `translator` is set, a programs file it wrote.
    func sceneWallpaper(_ number: Int, entries: [SyntheticScene.Entry], translator: Int?) throws -> Wallpaper {
        let id = WallpaperID(uuid: try #require(UUID(uuidString: "BBBBBBBB-0000-0000-0000-\(String(format: "%012d", number))")))
        let folder = "wallpapers/\(id)"
        // Where `LibraryLocation(home:)` puts the library.
        try home.writeSceneItem("Library/Application Support/Livepaper/\(folder)", entries: entries)
        if let translator {
            let file = location.root.appending(path: "\(folder)/\(ScenePrograms.fileName)")
            try ScenePrograms(translator: translator, tools: "the tools of old").write(to: file)
        }
        return Wallpaper(
            id: id, name: "Scene \(number)", importedAt: ImportBench.importedAt,
            fingerprint: Fingerprint(sha256: String(repeating: "\(number % 10)", count: 64)),
            optimisedCopy: try LibraryPath("\(folder)/scene.pkg"), poster: try LibraryPath("\(folder)/poster.heic"),
            details: WallpaperDetails(duration: 0, width: 1920, height: 1080, frameRate: 30, codec: "scene", byteCount: 1),
            scene: WallpaperScene(project: try LibraryPath("\(folder)/project.json"), width: 1920, height: 1080)
        )
    }

    var video: Wallpaper {
        get throws {
            Wallpaper(
                id: WallpaperID(uuid: UUID()), name: "Waves", importedAt: ImportBench.importedAt,
                fingerprint: Fingerprint(sha256: String(repeating: "f", count: 64)),
                optimisedCopy: try LibraryPath("wallpapers/video/wallpaper.mov"), poster: try LibraryPath("wallpapers/video/poster.heic"),
                details: WallpaperDetails(duration: 4, width: 1920, height: 1080, frameRate: 30, codec: "hevc", byteCount: 1)
            )
        }
    }
}

/// Writes a small poster of one colour as HEIC, saying `software` wrote it when that is given:
/// what a scene's poster file is before and after it is drawn from the scene (`ScenePoster.marker`).
func writePoster(to url: URL, software: String?) throws {
    let context = try #require(CGContext(
        data: nil, width: 16, height: 9, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ))
    context.setFillColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: 16, height: 9))
    let image = try #require(context.makeImage())
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let file = try #require(CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil))
    let properties: [CFString: Any] = software.map { [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFSoftware: $0]] } ?? [:]
    CGImageDestinationAddImage(file, image, properties as CFDictionary)
    #expect(CGImageDestinationFinalize(file))
}

/// An image file's mean colour, red, green and blue from 0 to 255, in sRGB.
func meanColour(at url: URL) throws -> [Int] {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    let side = 8
    var pixels = [UInt8](repeating: 0, count: side * side * 4)
    let sRGB = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    pixels.withUnsafeMutableBytes { buffer in
        let context = CGContext(
            data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: sRGB, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
        context?.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
    }
    return (0..<3).map { channel in
        stride(from: channel, to: pixels.count, by: 4).reduce(0) { $0 + Int(pixels[$1]) } / (side * side)
    }
}

/// Colours alike, give or take what lossy compression changes.
func isClose(_ colour: [Int], to expected: [Int], within tolerance: Int = 6) -> Bool {
    colour.count == expected.count && zip(colour, expected).allSatisfy { abs($0 - $1) <= tolerance }
}
