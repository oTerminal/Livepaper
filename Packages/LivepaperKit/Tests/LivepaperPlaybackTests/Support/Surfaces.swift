import Foundation
import LivepaperCore
import LivepaperPlayback

/// The library the supervisor's tests resolve paths in. Nothing is read from it.
let testLibrary = LibraryLocation(home: URL(filePath: "/Users/tester", directoryHint: .isDirectory))

extension SurfaceID {
    static func numbered(_ number: Int) -> SurfaceID {
        let digits = String(number)
        let padded = String(repeating: "0", count: 12 - digits.count) + digits
        guard let uuid = UUID(uuidString: "CCCCCCCC-0000-0000-0000-\(padded)") else { preconditionFailure("not a UUID: \(number)") }
        return SurfaceID(uuid: uuid)
    }
}

extension RenderState.Display {
    /// Display `display` showing wallpaper `wallpaper`, as the app writes it.
    static func numbered(
        _ display: Int,
        showing wallpaper: Int? = nil,
        presentation: Presentation = Presentation(),
        volume: Double = 0,
        userPaused: Bool = false
    ) -> RenderState.Display {
        let id = WallpaperID.numbered(wallpaper ?? display)
        return RenderState.Display(
            identity: .numbered(display),
            wallpaper: id,
            optimisedCopy: .known("wallpapers/\(id)/wallpaper.mov"),
            poster: .known("wallpapers/\(id)/poster.heic"),
            presentation: presentation,
            volume: volume,
            userPaused: userPaused
        )
    }
}

extension SurfaceWallpaper {
    /// Wallpaper `number` with its files resolved in `testLibrary`, as the supervisor hands it to a surface.
    static func numbered(_ number: Int, presentation: Presentation = Presentation(), volume: Double = 0) -> SurfaceWallpaper {
        let id = WallpaperID.numbered(number)
        return SurfaceWallpaper(
            wallpaper: id,
            video: testLibrary.url(for: .known("wallpapers/\(id)/wallpaper.mov")),
            poster: testLibrary.url(for: .known("wallpapers/\(id)/poster.heic")),
            presentation: presentation,
            volume: volume
        )
    }
}

extension SurfaceWallpaper {
    /// Wallpaper `number` as a scene of 3840 by 2160, resolved in `testLibrary`.
    static func scene(_ number: Int, presentation: Presentation = Presentation()) -> SurfaceWallpaper {
        let id = WallpaperID.numbered(number)
        return SurfaceWallpaper(
            wallpaper: id,
            video: testLibrary.url(for: .known("wallpapers/\(id)/scene.pkg")),
            poster: testLibrary.url(for: .known("wallpapers/\(id)/poster.heic")),
            presentation: presentation,
            volume: 0,
            scene: SurfaceScene(folder: testLibrary.wallpapers.appending(path: id.description), size: Size(width: 3840, height: 2160))
        )
    }
}

extension Presentation {
    static let fit = Presentation(fit: .fit)
}
