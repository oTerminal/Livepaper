import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import Synchronization
import Testing
import LivepaperCore
import LivepaperImport
import LivepaperScene

/// A library in a temporary home, and an importer into it whose wallpapers are numbered 1, 2, 3…
final class ImportBench: Sendable {
    let home: TemporaryFolder
    let location: LibraryLocation
    let store: FileLibraryStore
    let library: StoredLibrary
    private let count = Mutex(0)

    static let importedAt = Date(timeIntervalSince1970: 1_790_000_000)

    init() throws {
        home = try TemporaryFolder()
        location = LibraryLocation(home: home.url)
        store = FileLibraryStore(manifest: location.manifest)
        library = try StoredLibrary(store: store)
    }

    /// `sceneDrawing` draws a scene's poster; with none, it is cut from the item's preview.
    func importer(
        library: (any ImportLibrary)? = nil, ffmpeg: FFmpegTool? = nil, shaderTools: ShaderTools? = nil,
        sceneDrawing: (any SceneDrawing.Type)? = nil
    ) -> Importer {
        Importer(
            location: location, library: library ?? self.library, ffmpeg: ffmpeg, shaderTools: shaderTools,
            sceneDrawing: sceneDrawing, makeID: { self.nextID() }, now: { Self.importedAt }
        )
    }

    private func nextID() -> WallpaperID {
        let number = count.withLock { count in
            count += 1
            return count
        }
        return WallpaperID(uuid: UUID(uuidString: "AAAAAAAA-0000-0000-0000-\(String(format: "%012d", number))")!)
    }

    // MARK: What is on disk

    func names(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    /// What an import must never leave behind.
    var stagingResidue: [String] { names(in: location.staging) }

    var wallpaperFolders: [String] { names(in: location.root.appending(path: "wallpapers")) }

    /// The library as the next launch will find it.
    func savedLibrary() throws -> Library { try store.load() }
}

/// The helper built by `Helpers/ffmpeg/build.sh`, or the one `LIVEPAPER_FFMPEG` points at.
///
/// A checkout that has not built it skips the tests that need it. CI sets
/// `LIVEPAPER_REQUIRE_FFMPEG`, which turns the skip into a failure.
enum Helper {
    static let tool: FFmpegTool? = {
        let environment = ProcessInfo.processInfo.environment
        let repository = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../../../../..", directoryHint: .isDirectory).standardizedFileURL
        return FFmpegTool.locate(
            replacement: environment["LIVEPAPER_FFMPEG"].map { URL(filePath: $0) },
            bundled: repository.appending(path: "Helpers/ffmpeg/out/ffmpeg")
        )
    }()

    static let isRequired = ProcessInfo.processInfo.environment["LIVEPAPER_REQUIRE_FFMPEG"] == "1"
    static let shouldRun = tool != nil || isRequired

    static func required() throws -> FFmpegTool {
        try #require(tool, "the ffmpeg helper is not built: run `make ffmpeg`")
    }
}

struct Picture {
    /// The mean, 0 to 255.
    var brightness: Double
    /// In pixels.
    var size: [Int]
}

/// An image file's mean brightness and its size.
func picture(at url: URL) throws -> Picture {
    let source = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
    let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
    var pixels = [UInt8](repeating: 0, count: 64 * 64)
    pixels.withUnsafeMutableBytes { buffer in
        let context = CGContext(
            data: buffer.baseAddress, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 64,
            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
        )
        context?.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
    }
    return Picture(brightness: Double(pixels.reduce(0) { $0 + Int($1) }) / Double(pixels.count), size: [image.width, image.height])
}

/// A movie file's video rate, in bits per second: its video samples' size over the track's duration, as AVFoundation reads it.
func videoBitRate(of url: URL) async throws -> Double {
    let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .video).first)
    return Double(try await track.load(.estimatedDataRate))
}

/// The same for the movie's audio.
func audioBitRate(of url: URL) async throws -> Double {
    let track = try #require(try await AVURLAsset(url: url).loadTracks(withMediaType: .audio).first)
    return Double(try await track.load(.estimatedDataRate))
}
