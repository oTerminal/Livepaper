import Foundation
import LivepaperCore

/// Identifies one surface: the identifier WallpaperAgent gives it at acquire.
public struct SurfaceID: Hashable, Sendable, CustomStringConvertible {
    public let uuid: UUID

    public init(uuid: UUID) {
        self.uuid = uuid
    }

    public var description: String { uuid.uuidString }
}

/// The size of a surface as the agent gives it: points, and the scale that
/// turns them into pixels.
public struct SurfaceGeometry: Equatable, Sendable {
    public var size: Size
    public var scale: Double

    public init(size: Size, scale: Double) {
        self.size = size
        self.scale = scale
    }

    public var pixelSize: Size {
        Size(width: size.width * scale, height: size.height * scale)
    }
}

/// What a surface is asked to show: one wallpaper, its files already resolved
/// inside the library.
public struct SurfaceWallpaper: Equatable, Sendable {
    public var wallpaper: WallpaperID
    /// The optimised copy; for a scene, its package, which no video engine opens.
    public var video: URL
    public var poster: URL
    public var presentation: Presentation
    /// 0 to 1. At 0 the audio track is not opened.
    public var volume: Double
    /// Set when the wallpaper is a scene, which is drawn rather than played.
    public var scene: SurfaceScene?

    public init(
        wallpaper: WallpaperID, video: URL, poster: URL, presentation: Presentation, volume: Double, scene: SurfaceScene? = nil
    ) {
        self.wallpaper = wallpaper
        self.video = video
        self.poster = poster
        self.presentation = presentation
        self.volume = volume
        self.scene = scene
    }
}

/// A scene a surface draws: its folder in the library, which a `SceneDrawing`
/// loads, and the size it is laid out in, which the presentation fits to the surface.
public struct SurfaceScene: Equatable, Sendable {
    public var folder: URL
    public var size: Size

    public init(folder: URL, size: Size) {
        self.folder = folder
        self.size = size
    }
}

/// What a surface is doing, as the playback mapping reads it.
public enum SurfacePlaybackState: Equatable, Sendable {
    /// The neutral colour: nothing to show.
    case nothing
    /// The poster, with no decoder.
    case still
    case playing
    /// Not advancing; the readers and the decoder are kept, so resuming is instant.
    case paused
    /// Not advancing; the readers and the decoder are released, and the last
    /// picture is kept where the renderer allows.
    case suspended
}

/// New pictures a surface showed over a window, and how many the wallpaper's
/// frame rate should have shown: what `judgeProgress` takes. With them, the
/// frames the engine fed the renderer over the same window, which tell a
/// surface the window server does not composite from one that stalled.
public struct PictureCount: Equatable, Sendable {
    public var displayed: Int
    public var expected: Int
    public var fed: Int
    /// A scene's: the frames its display link asked for over the window. Nil for a video.
    public var asked: Int?
    /// A scene's display link asked for too few frames while its engine stood
    /// ready to draw them. The system does not ask for frames of a surface it
    /// does not show, so this is a covered surface, never a stall.
    public var withheld: Bool
    /// A scene's: the pictures the window server presented, for the log. Nil for a video.
    public var presented: Int?

    public init(displayed: Int, expected: Int, fed: Int, asked: Int? = nil, withheld: Bool = false, presented: Int? = nil) {
        self.displayed = displayed
        self.expected = expected
        self.fed = fed
        self.asked = asked
        self.withheld = withheld
        self.presented = presented
    }
}

/// One surface's layer tree and the engines on it, as `PlaybackSupervisor`
/// drives it. `SurfaceLayers` is the real one; the supervisor's tests use a fake.
///
/// Not `Sendable`: it lives on the actor of whoever owns it, which in the
/// extension is the main actor, and its async methods run there.
public protocol SurfacePlayback: AnyObject {
    var state: SurfacePlaybackState { get }
    /// The wallpaper being played or held, if any.
    var wallpaper: SurfaceWallpaper? { get }

    /// Plays `wallpaper`. The same video with another presentation or volume
    /// is changed in place; another video is switched to, crossfading when asked.
    func show(_ wallpaper: SurfaceWallpaper, crossfade: Bool) async
    /// Holds the wallpaper's poster as a still, laid out as its video would be,
    /// and releases the decoder.
    func holdStill(poster wallpaper: SurfaceWallpaper) async
    /// Shows the neutral colour and releases everything.
    func showNothing() async

    /// Stops advancing, keeping the readers, with a rate ramp.
    func pause() async
    /// Advances again after `pause()` or `suspend()`.
    func resume() async
    /// Stops advancing and releases the readers and the decoder.
    func suspend() async

    /// Tries a recovery inside the process: `.flush`, `.rebuildSurface` or
    /// `.rebuildPipeline`. `.restartAgent` is the app's, not the surface's.
    func recover(_ level: RecoveryLevel) async
    /// Counts the new pictures shown over `window`, and the frames fed to the
    /// renderer meanwhile. `nil` when nothing plays.
    func displayedPictures(over window: Duration) async -> PictureCount?

    /// Lays the tree out again for a new size, without animation.
    func layout(surface: SurfaceGeometry)
}
