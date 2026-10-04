import CoreGraphics
import Foundation
import ImageIO
import LivepaperCore
import LivepaperScene
import Metal
import UniformTypeIdentifiers

/// A scene's poster drawn from the scene itself: what the
/// desktop holds when the extension has no picture of the scene of its own
/// (after a restart while stopped; a scene that cannot load), the
/// library's tiles, the popover and the lock screen before the first frame.
///
/// A Workshop item's preview is no poster for it: it can be a few hundred
/// pixels wide (250×141 was seen), stretched over a display it is a blur, and it
/// is often another picture altogether. So the scene is drawn offscreen, with
/// what draws it on the desktop (`SceneDrawing`), at its own size with its
/// longest side at most `longestSide`, `time` seconds in, after `leadIn` of
/// pictures at the rate a scene is drawn at.
///
/// It runs where import runs, never in the extension: at import once the scene
/// is prepared, with the poster cut from the preview when it cannot be drawn
/// (`makeScenePoster`); and at launch for every scene whose poster was not drawn
/// by this build and can be now (`refresh`). A drawn poster says so in its file
/// (`marker`), so each is drawn once.
public enum ScenePoster {
    public enum Outcome: Equatable, Sendable {
        /// The poster is the scene's own picture, this many pixels.
        case drawn(width: Int, height: Int)
        /// Nothing was written, for this reason; the poster is the one cut from the item's preview.
        case notDrawn(reason: String)
    }

    /// The scene time a poster shows, in seconds. The samples' particles had
    /// all spread by then (A Lonely Winter's petals by 5 s, Gaze's fog near the
    /// water only by about 10 s), and it is well inside the half minute a
    /// drawing simulates to catch up with a time it jumps to.
    public static let time = 10.0
    /// Drawn for this long before `time`, so that effects that carry a picture
    /// from one frame to the next have one: Backstreet Lofi's motion-blurred fan
    /// is a dark blot in a first picture, and itself after a second.
    static let leadIn = 1.0
    /// The longest side a poster is drawn at: a 4K display's, which the largest
    /// sample (6000×3375) is brought down to. A smaller scene is drawn at its own size.
    static let longestSide = 3840.0
    /// What a drawn poster records as the software that wrote it (its TIFF
    /// `Software`). A poster without it, or with an earlier build's, is drawn again.
    /// It names the translator, so programs translated anew (`ScenePreparation.refresh`)
    /// draw the poster anew too.
    public static let marker = "Livepaper scene poster 1, translator \(ScenePrograms.currentTranslator)"

    /// The size a poster of a scene of `size` is drawn at, in pixels.
    public static func pixels(for size: Size) -> (width: Int, height: Int) {
        let scale = min(1, longestSide / max(size.width, size.height, 1))
        return (max(1, Int((size.width * scale).rounded())), max(1, Int((size.height * scale).rounded())))
    }

    /// Draws the scene in `folder` with `drawingType` and writes it whole to
    /// `destination`, replacing what was there; on a thread of its own, since it
    /// waits for the GPU. Only a cancel throws: a scene that cannot be drawn is
    /// an outcome, and leaves `destination` as it was.
    public static func draw(
        _ folder: URL, size: Size, with drawingType: any SceneDrawing.Type, to destination: URL
    ) async throws -> Outcome {
        try await draw(folder, size: size, drawing: SceneDrawingType(drawingType), to: destination)
    }

    static func draw(_ folder: URL, size: Size, drawing: SceneDrawingType, to destination: URL) async throws -> Outcome {
        try await onOwnThread { cancellation in
            try drawNow(folder, size: size, drawing.type, to: destination, cancellation: cancellation)
        }
    }

    /// Whether the poster at `poster` was drawn from its scene by this build.
    public static func isDrawn(_ poster: URL) -> Bool {
        guard
            let source = CGImageSourceCreateWithURL(poster as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
        else { return false }
        return tiff[kCGImagePropertyTIFFSoftware] as? String == marker
    }

    /// Whether `wallpaper` is a scene whose poster the app should draw: one not
    /// drawn by this build, of a scene that can be drawn, which is one whose
    /// programs are the current translator's (`ScenePreparation.refresh` comes first).
    public static func needsDrawing(_ wallpaper: Wallpaper, in location: LibraryLocation) -> Bool {
        guard let scene = wallpaper.scene else { return false }
        let folder = location.url(for: scene.project).deletingLastPathComponent()
        guard ScenePrograms.translator(in: folder) == ScenePrograms.currentTranslator else { return false }
        return !isDrawn(location.url(for: wallpaper.poster))
    }

    /// Draws again, one scene at a time and off the caller's actor, the poster
    /// of each scene in `wallpapers` that needs it (`needsDrawing`). `log`
    /// hears each outcome as it comes. The file is replaced whole, so no reader
    /// sees half of one; a scene that cannot be drawn keeps its poster and is
    /// tried again at the next launch. A cancel stops it where it is.
    public static func refresh(
        _ wallpapers: [Wallpaper], in location: LibraryLocation, drawingType: any SceneDrawing.Type,
        log: @escaping @Sendable (Wallpaper, Outcome) async -> Void
    ) async -> [WallpaperID: Outcome] {
        await refresh(wallpapers, in: location, drawing: SceneDrawingType(drawingType), log: log)
    }

    @concurrent
    private static func refresh(
        _ wallpapers: [Wallpaper], in location: LibraryLocation, drawing: SceneDrawingType,
        log: @escaping @Sendable (Wallpaper, Outcome) async -> Void
    ) async -> [WallpaperID: Outcome] {
        // Which scenes need it is read from their files, on a thread of its own, as all reading is.
        let needing = (try? await onOwnThread { _ in wallpapers.filter { needsDrawing($0, in: location) } }) ?? []
        var outcomes: [WallpaperID: Outcome] = [:]
        for wallpaper in needing where !Task.isCancelled {
            guard let scene = wallpaper.scene else { continue }
            let folder = location.url(for: scene.project).deletingLastPathComponent()
            let size = Size(width: Double(scene.width), height: Double(scene.height))
            let poster = location.url(for: wallpaper.poster)
            guard let outcome = try? await draw(folder, size: size, drawing: drawing, to: poster) else { break }
            outcomes[wallpaper.id] = outcome
            await log(wallpaper, outcome)
        }
        return outcomes
    }

    // MARK: The work, on a thread of its own

    static func drawNow(
        _ folder: URL, size: Size, _ drawingType: any SceneDrawing.Type, to destination: URL, cancellation: Cancellation
    ) throws -> Outcome {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            return .notDrawn(reason: "there is no Metal device")
        }
        let drawing: any SceneDrawing
        do {
            drawing = try drawingType.init(folder: folder, device: device)
        } catch {
            return .notDrawn(reason: (error as? any LocalizedError)?.errorDescription ?? "\(error)")
        }
        let (width, height) = pixels(for: size)
        guard let picture = try picture(of: drawing, width: width, height: height, on: queue, cancellation: cancellation) else {
            return .notDrawn(reason: "the GPU did not draw it")
        }
        do {
            try write(picture, to: destination)
        } catch {
            return .notDrawn(reason: "\(destination.lastPathComponent) could not be written: \(error)")
        }
        return .drawn(width: width, height: height)
    }

    /// The scene at `time`, after `leadIn` of pictures, each finished before the
    /// next is drawn, as the drawing's own buffers expect. Nil when the GPU fails.
    private static func picture(
        of drawing: any SceneDrawing, width: Int, height: Int, on queue: any MTLCommandQueue, cancellation: Cancellation
    ) throws -> CGImage? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: SceneFolder.pixelFormat, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        let bytesPerRow = width * 4
        guard
            let texture = queue.device.makeTexture(descriptor: descriptor),
            let pixels = queue.device.makeBuffer(length: bytesPerRow * height, options: .storageModeShared)
        else { return nil }
        drawing.resize(width: width, height: height)
        let frames = Int((leadIn * LivepaperScene.framesPerSecond).rounded())
        for frame in 0...frames {
            try cancellation.check()
            guard let buffer = queue.makeCommandBuffer() else { return nil }
            buffer.label = "livepaper.scene-poster"
            // Counted back from `time`, so that the last picture is at `time` exactly.
            drawing.draw(into: texture, on: buffer, at: time - Double(frames - frame) / LivepaperScene.framesPerSecond)
            if frame == frames, let blit = buffer.makeBlitCommandEncoder() {
                blit.copy(
                    from: texture, sourceSlice: 0, sourceLevel: 0, sourceOrigin: MTLOrigin(),
                    sourceSize: MTLSize(width: width, height: height, depth: 1), to: pixels, destinationOffset: 0,
                    destinationBytesPerRow: bytesPerRow, destinationBytesPerImage: bytesPerRow * height
                )
                blit.endEncoding()
            }
            buffer.commit()
            buffer.waitUntilCompleted()
            guard buffer.status == .completed else { return nil }
        }
        // The slot's own pixels: BGRA, opaque, sRGB (`SurfaceTree`).
        let data = Data(bytes: pixels.contents(), count: bytesPerRow * height)
        guard let provider = CGDataProvider(data: data as CFData), let sRGB = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: bytesPerRow, space: sRGB,
            bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.noneSkipFirst.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    /// HEIC, as every poster is, marked as drawn, and written whole: to a file
    /// beside it first, then moved over it.
    private static func write(_ picture: CGImage, to destination: URL) throws {
        let data = NSMutableData()
        guard let file = CGImageDestinationCreateWithData(data, UTType.heic.identifier as CFString, 1, nil) else {
            throw ArtefactError.posterNotWritten
        }
        let properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.85,
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFSoftware: marker],
        ]
        CGImageDestinationAddImage(file, picture, properties as CFDictionary)
        guard CGImageDestinationFinalize(file) else { throw ArtefactError.posterNotWritten }
        try (data as Data).write(to: destination, options: .atomic)
    }
}

/// What draws scenes, carried to the thread that draws a poster. A type is only ever read.
struct SceneDrawingType: @unchecked Sendable {
    let type: any SceneDrawing.Type

    init(_ type: any SceneDrawing.Type) {
        self.type = type
    }
}
