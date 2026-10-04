import Foundation
import LivepaperCore

/// The library as an import sees it. Whoever holds the `Library` (the app, the
/// CLI) stands behind this, so that there is one writer of the manifest however
/// many imports are running.
public protocol ImportLibrary: Sendable {
    /// The wallpaper that was imported from a source file with this fingerprint, if there is one.
    func wallpaper(withFingerprint fingerprint: Fingerprint) async throws -> Wallpaper?
    func wallpaper(withID id: WallpaperID) async throws -> Wallpaper?
    /// Adds the wallpaper and saves the manifest, or throws and does neither.
    /// Called when the wallpaper's files are in place.
    func insert(_ wallpaper: Wallpaper) async throws
}

/// A `Library` kept in step with its store: every insert is saved before it counts.
public actor StoredLibrary: ImportLibrary {
    public private(set) var library: Library
    private let store: any LibraryStore

    public init(store: any LibraryStore) throws {
        self.store = store
        library = try store.load()
    }

    public func wallpaper(withFingerprint fingerprint: Fingerprint) -> Wallpaper? {
        library.wallpaper(withFingerprint: fingerprint)
    }

    public func wallpaper(withID id: WallpaperID) -> Wallpaper? {
        library[id]
    }

    public func insert(_ wallpaper: Wallpaper) throws {
        let updated = try library.inserting(wallpaper)
        try store.save(updated)
        library = updated
    }
}

/// Clears away what an import that was killed left behind: everything in
/// `.staging/`, and any wallpaper folder the manifest does not list (the kill
/// came between the rename and the manifest). For the app to run at launch,
/// before any import starts. Answers what it removed.
///
/// Wallpaper folders are judged against the manifest on disk and no other
/// library. When that manifest cannot be read, the library the app goes on
/// with is an older one (`FileLibraryStore` falls back), and against an older
/// library the newest wallpapers would look like leftovers. So then, and when
/// there is no manifest at all, only `.staging/` is cleared.
@discardableResult
public func sweepInterruptedImports(in location: LibraryLocation) throws -> [URL] {
    let files = FileManager.default
    var leftovers = (try? files.contentsOfDirectory(at: location.staging, includingPropertiesForKeys: nil)) ?? []

    if let manifest = try? Data(contentsOf: location.manifest), let library = try? Library.decode(manifest) {
        let listed = Set(library.wallpapers.map(\.id.description))
        let folders = (try? files.contentsOfDirectory(at: location.wallpapers, includingPropertiesForKeys: nil)) ?? []
        leftovers += folders.filter { !listed.contains($0.lastPathComponent) }
    }
    for url in leftovers {
        try files.removeItem(at: url)
    }
    return leftovers
}
