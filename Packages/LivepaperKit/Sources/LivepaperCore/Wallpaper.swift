import Foundation

/// The SHA-256 of a source file, taken before any conversion. Two imports of
/// the same bytes have the same fingerprint, whatever the files are called.
public struct Fingerprint: Hashable, Codable, Sendable, CustomStringConvertible {
    /// 64 lowercase hex digits.
    public let sha256: String

    public init(sha256: String) {
        self.sha256 = sha256.lowercased()
    }

    // Persisted as a bare string.
    public init(from decoder: any Decoder) throws {
        self.init(sha256: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(sha256)
    }

    public var description: String { sha256 }
}

/// What the file details panel shows about a wallpaper's optimised copy, or
/// about a scene: its size, the rate it is drawn at and the bytes of its folder.
public struct WallpaperDetails: Codable, Equatable, Sendable {
    /// In seconds. A scene has none.
    public var duration: Double
    /// In pixels.
    public var width: Int
    public var height: Int
    public var frameRate: Double
    public var codec: String
    public var byteCount: Int

    public init(duration: Double, width: Int, height: Int, frameRate: Double, codec: String, byteCount: Int) {
        self.duration = duration
        self.width = width
        self.height = height
        self.frameRate = frameRate
        self.codec = codec
        self.byteCount = byteCount
    }
}

/// Whether a wallpaper plays a video or draws a scene.
public enum WallpaperKind: String, Equatable, Sendable {
    case video
    case scene
}

/// A Wallpaper Engine scene as the library keeps it: the item's own files,
/// which the extension draws live rather than plays.
public struct WallpaperScene: Codable, Equatable, Sendable {
    /// The item's `project.json`. Its folder holds everything else the scene needs.
    public var project: LibraryPath
    /// The size the scene is laid out in, in its own units, from its
    /// `orthogonalprojection`: what a presentation fits to a display.
    public var width: Int
    public var height: Int

    public init(project: LibraryPath, width: Int, height: Int) {
        self.project = project
        self.width = width
        self.height = height
    }

    public var size: Size {
        Size(width: Double(width), height: Double(height))
    }
}

/// A looping video, or a Wallpaper Engine scene drawn live, in the library,
/// that can be shown on a display.
///
/// Its files are named by paths relative to the library root.
public struct Wallpaper: Codable, Equatable, Identifiable, Sendable {
    public let id: WallpaperID
    public var name: String
    public var isFavourite: Bool
    public let importedAt: Date
    public var fingerprint: Fingerprint
    /// The one video file the library keeps for a video. For a scene, its
    /// package: a Livepaper that knows only video fails to play it, and holds
    /// the poster instead.
    public var optimisedCopy: LibraryPath
    public var poster: LibraryPath
    public var hoverPreview: LibraryPath?
    public var details: WallpaperDetails
    public var presentation: Presentation
    /// 0 to 1. Wallpapers are imported silent.
    public var volume: Double
    /// Set for a Wallpaper Engine scene, nil for a video. Added in schema 1.1,
    /// so a manifest written before it reads as all video.
    public var scene: WallpaperScene?

    public init(
        id: WallpaperID,
        name: String,
        isFavourite: Bool = false,
        importedAt: Date,
        fingerprint: Fingerprint,
        optimisedCopy: LibraryPath,
        poster: LibraryPath,
        hoverPreview: LibraryPath? = nil,
        details: WallpaperDetails,
        presentation: Presentation = Presentation(),
        volume: Double = 0,
        scene: WallpaperScene? = nil
    ) {
        self.id = id
        self.name = name
        self.isFavourite = isFavourite
        self.importedAt = importedAt
        self.fingerprint = fingerprint
        self.optimisedCopy = optimisedCopy
        self.poster = poster
        self.hoverPreview = hoverPreview
        self.details = details
        self.presentation = presentation
        self.volume = volume
        self.scene = scene
    }

    public var kind: WallpaperKind {
        scene == nil ? .video : .scene
    }
}
