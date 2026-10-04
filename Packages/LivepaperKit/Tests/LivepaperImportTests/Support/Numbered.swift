import Foundation
import LivepaperCore
import LivepaperImport

// Readable, fixed identifiers: import 1 is always the same import.
private func numberedUUID(_ prefix: String, _ number: Int) -> UUID {
    guard let uuid = UUID(uuidString: String(format: "\(prefix)-0000-0000-0000-%012d", number)) else {
        preconditionFailure("not a UUID: \(prefix), \(number)")
    }
    return uuid
}

extension UUID {
    /// The import list's row for candidate `number`.
    static func row(_ number: Int) -> UUID {
        numberedUUID("CCCCCCCC", number)
    }
}

extension ImportCandidate {
    /// `Harbour 1.mov` and so on, in a folder that need not be there.
    static func numbered(_ number: Int) -> ImportCandidate {
        ImportCandidate(source: URL(filePath: "/Users/tester/Movies/Harbour \(number).mov"), name: "Harbour \(number)")
    }
}

extension Wallpaper {
    /// Wallpaper `number`, as an import of candidate `number` would make it.
    static func numbered(_ number: Int, fingerprint: Fingerprint? = nil) -> Wallpaper {
        let id = WallpaperID(uuid: numberedUUID("AAAAAAAA", number))
        guard
            let optimisedCopy = try? LibraryPath("wallpapers/\(id)/wallpaper.mov"),
            let poster = try? LibraryPath("wallpapers/\(id)/poster.heic")
        else { preconditionFailure("not a library path: \(id)") }
        return Wallpaper(
            id: id,
            name: "Harbour \(number)",
            importedAt: Moment.after(Double(number) * 60),
            fingerprint: fingerprint ?? Fingerprint(sha256: String(format: "%064d", number)),
            optimisedCopy: optimisedCopy,
            poster: poster,
            details: WallpaperDetails(duration: 12.5, width: 3840, height: 2160, frameRate: 60, codec: "hevc", byteCount: 48_000_000)
        )
    }
}
