import Foundation
import Metal

/// Draws a scene's pictures with Metal: the seam between the extension's scene
/// engine and whatever reads and draws a Wallpaper Engine scene:
/// `WallpaperEngineScene`, or a test's stand-in.
///
/// Made off the main thread, since loading can take a while, then used on the
/// engine's render thread only, one call at a time.
public protocol SceneDrawing: AnyObject {
    /// Reads the scene in `folder`, a scene wallpaper's folder in the library
    /// (`SceneFolder`), and makes on `device` what drawing it needs. Throws
    /// when the scene cannot be drawn; the surface then holds its poster.
    init(folder: URL, device: any MTLDevice) throws

    /// Encodes the picture at `time` seconds of scene time into `texture`,
    /// on `commandBuffer`. The engine commits the buffer and presents the
    /// texture. `texture` is `SceneFolder.pixelFormat`, of the size `resize` last gave.
    func draw(into texture: any MTLTexture, on commandBuffer: any MTLCommandBuffer, at time: Double)

    /// The textures `draw` is given are this many pixels from now on. Called
    /// before the first `draw`, and whenever the surface's size changes.
    func resize(width: Int, height: Int)

    /// What of the scene is not drawn as it asks, or is stood in for, for the log.
    var notes: [String] { get }

    /// The scene's sounds, made once after loading, on the loading queue, and
    /// then played by the engine's owner, apart from drawing. Nil for none.
    func makeSoundtrack() -> SceneSoundtrack?

    /// Where the pointer is over the surface's display, 0 to 1 from the top
    /// left, before a `draw`; for a scene that follows it (parallax).
    func pointerMoved(to position: SIMD2<Float>)
}

extension SceneDrawing {
    public var notes: [String] { [] }
    public func makeSoundtrack() -> SceneSoundtrack? { nil }
    public func pointerMoved(to position: SIMD2<Float>) {}
}

/// A scene wallpaper's folder in the library, as the import writes it and a
/// `SceneDrawing` reads it: the item's own `project.json`, package (named as
/// `package(for:)` says) and preview, and the library's poster and hover preview.
public enum SceneFolder {
    public static let project = "project.json"
    public static let poster = "poster.heic"
    public static let hoverPreview = "hover.mov"

    /// What a scene is drawn into: the drawables of the surface's Metal slot.
    public static let pixelFormat = MTLPixelFormat.bgra8Unorm

    /// The package a project's scene lives in, in the item's own folder: its
    /// `file` with `.pkg` for `.json` (`scene.json`, `scene.pkg`).
    public static func itemPackage(for sceneFile: String) -> String {
        (sceneFile as NSString).deletingPathExtension + ".pkg"
    }

    /// The same package in the library, under a name a `LibraryPath` can hold:
    /// in each step of it, a character a library path refuses, or a `.` it
    /// would start with, becomes `_` (`scene.json`, `scene.pkg`; `night
    /// scene.json`, `night_scene.pkg`). A name it could hold is left as it is.
    public static func package(for sceneFile: String) -> String {
        let steps = itemPackage(for: sceneFile).split(separator: "/", omittingEmptySubsequences: false).map { step in
            String(step.unicodeScalars.enumerated().map { index, scalar -> Character in
                switch scalar {
                case "a"..."z", "A"..."Z", "0"..."9", "-", "_": Character(scalar)
                case "." where index > 0: "."
                default: "_"
                }
            })
        }
        return steps.joined(separator: "/")
    }
}
