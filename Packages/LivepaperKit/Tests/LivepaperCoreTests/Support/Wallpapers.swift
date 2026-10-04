import Foundation
import LivepaperCore

extension Wallpaper {
    /// Wallpaper `number`, imported `number` minutes after launch.
    static func numbered(_ number: Int, name: String? = nil, isFavourite: Bool = false) -> Wallpaper {
        let id = WallpaperID.numbered(number)
        let digits = String(number)
        return Wallpaper(
            id: id,
            name: name ?? "Wallpaper \(number)",
            isFavourite: isFavourite,
            importedAt: Moment.after(Double(number) * 60),
            fingerprint: Fingerprint(sha256: String(repeating: "0", count: 64 - digits.count) + digits),
            optimisedCopy: .known("wallpapers/\(id)/wallpaper.mov"),
            poster: .known("wallpapers/\(id)/poster.heic"),
            hoverPreview: .known("wallpapers/\(id)/hover.mov"),
            details: WallpaperDetails(duration: 12.5, width: 3840, height: 2160, frameRate: 60, codec: "hevc", byteCount: 48_000_000),
            presentation: Presentation(),
            volume: 0
        )
    }
}

extension Library {
    static func of(_ wallpapers: Wallpaper...) throws -> Library {
        try of(contentsOf: wallpapers)
    }

    static func of(contentsOf wallpapers: [Wallpaper]) throws -> Library {
        try wallpapers.reduce(Library()) { try $0.inserting($1) }
    }
}
