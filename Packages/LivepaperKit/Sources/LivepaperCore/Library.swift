import Foundation

public enum LibraryError: Error, Equatable, Sendable {
    case noSuchWallpaper(WallpaperID)
    case alreadyInLibrary(WallpaperID)
    /// The same source file was imported before, as this wallpaper.
    case duplicate(of: WallpaperID)
    case emptyName
}

/// A name as typed, for a wallpaper or a playlist, as the library keeps it:
/// without the spaces and line breaks around it. Nil when nothing is left, which
/// every rename and a new playlist refuse, and a name prompt's button waits for.
public func acceptedName(_ typed: String) -> String? {
    let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
    return name.isEmpty ? nil : name
}

/// The user's collection of wallpapers.
///
/// A value: every operation returns a new library and leaves this one as it
/// was, which is what makes undo a matter of keeping the old one.
public struct Library: Equatable, Sendable {
    /// 1.1 added a wallpaper's `scene`.
    public static let schemaVersion = SchemaVersion(major: 1, minor: 1)

    /// In the order they were imported.
    public private(set) var wallpapers: [Wallpaper]

    public init() {
        wallpapers = []
    }

    public subscript(id: WallpaperID) -> Wallpaper? {
        wallpapers.first { $0.id == id }
    }

    public var favourites: [Wallpaper] {
        wallpapers.filter(\.isFavourite)
    }

    /// The wallpaper that was imported from a source file with this
    /// fingerprint, so that an import can stop before converting anything.
    public func wallpaper(withFingerprint fingerprint: Fingerprint) -> Wallpaper? {
        wallpapers.first { $0.fingerprint == fingerprint }
    }

    // MARK: Changes

    /// The last step of an import.
    public func inserting(_ wallpaper: Wallpaper) throws -> Library {
        guard self[wallpaper.id] == nil else { throw LibraryError.alreadyInLibrary(wallpaper.id) }
        if let existing = self.wallpaper(withFingerprint: wallpaper.fingerprint) {
            throw LibraryError.duplicate(of: existing.id)
        }
        var library = self
        library.wallpapers.append(wallpaper)
        return library
    }

    public func renaming(_ id: WallpaperID, to name: String) throws -> Library {
        guard let name = acceptedName(name) else { throw LibraryError.emptyName }
        return try updating(id) { $0.name = name }
    }

    public func settingFavourite(_ isFavourite: Bool, for id: WallpaperID) throws -> Library {
        try updating(id) { $0.isFavourite = isFavourite }
    }

    /// The wallpaper's own presentation, which every display showing it takes.
    public func settingPresentation(_ presentation: Presentation, for id: WallpaperID) throws -> Library {
        try updating(id) { $0.presentation = presentation }
    }

    /// Kept between 0 and 1, and a volume that is not a number is silent.
    public func settingVolume(_ volume: Double, for id: WallpaperID) throws -> Library {
        let volume = volume.isFinite ? min(max(volume, 0), 1) : 0
        return try updating(id) { $0.volume = volume }
    }

    /// A deleted wallpaper and where it was, which is all that undo needs.
    public struct Removal: Equatable, Sendable {
        public let wallpaper: Wallpaper
        let index: Int
    }

    public func deleting(_ id: WallpaperID) throws -> (library: Library, removal: Removal) {
        let index = try index(of: id)
        var library = self
        let wallpaper = library.wallpapers.remove(at: index)
        return (library, Removal(wallpaper: wallpaper, index: index))
    }

    /// Undoes a delete: the wallpaper goes back where it was.
    public func restoring(_ removal: Removal) throws -> Library {
        guard self[removal.wallpaper.id] == nil else { throw LibraryError.alreadyInLibrary(removal.wallpaper.id) }
        var library = self
        library.wallpapers.insert(removal.wallpaper, at: min(removal.index, wallpapers.count))
        return library
    }

    private func updating(_ id: WallpaperID, _ change: (inout Wallpaper) -> Void) throws -> Library {
        let index = try index(of: id)
        var library = self
        change(&library.wallpapers[index])
        return library
    }

    private func index(of id: WallpaperID) throws -> Int {
        guard let index = wallpapers.firstIndex(where: { $0.id == id }) else { throw LibraryError.noSuchWallpaper(id) }
        return index
    }

    // MARK: Sort and search

    /// Persisted by name, in the app state.
    public enum SortOrder: String, CaseIterable, Codable, Sendable {
        case newestFirst
        case oldestFirst
        case name
    }

    public func sorted(by order: SortOrder) -> [Wallpaper] {
        wallpapers.sorted(by: order)
    }

    /// Wallpapers whose name contains every word of the query, without regard
    /// to case or accents. An empty query finds everything.
    public func search(_ query: String) -> [Wallpaper] {
        let words = query.foldedForSearch.split(whereSeparator: \.isWhitespace)
        return wallpapers.filter { wallpaper in
            let name = wallpaper.name.foldedForSearch
            return words.allSatisfy(name.contains)
        }
    }
}

extension Sequence<Wallpaper> {
    public func sorted(by order: Library.SortOrder) -> [Wallpaper] {
        sorted { lhs, rhs in
            let comparison: ComparisonResult = switch order {
            case .newestFirst: rhs.importedAt.compare(lhs.importedAt)
            case .oldestFirst: lhs.importedAt.compare(rhs.importedAt)
            case .name: lhs.name.compare(rhs.name, options: [.caseInsensitive, .diacriticInsensitive, .numeric], range: nil, locale: nil)
            }
            // Equal keys fall back to the identifier, so the order never depends on where the sort started.
            return comparison == .orderedSame ? lhs.id.description < rhs.id.description : comparison == .orderedAscending
        }
    }
}

extension String {
    // No locale: the same library gives the same results on every Mac.
    fileprivate var foldedForSearch: String {
        folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}

// MARK: - Manifest

extension Library: Codable {
    private enum CodingKeys: String, CodingKey {
        case version, wallpapers
    }

    public func encode() throws -> Data {
        try PersistedJSON.encoder().encode(self)
    }

    public static func decode(_ data: Data) throws -> Library {
        try PersistedJSON.decoder().decode(Library.self, from: data)
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(SchemaVersion.self, forKey: .version)
        // When major version 2 arrives, version 1 is decoded here by a frozen
        // copy of this shape and migrated, and `library-v1.0.json` proves it.
        try version.requireReadable(by: Self.schemaVersion)

        wallpapers = try container.decode([Wallpaper].self, forKey: .wallpapers)
        guard Set(wallpapers.map(\.id)).count == wallpapers.count else {
            throw DecodingError.dataCorruptedError(
                forKey: .wallpapers, in: container, debugDescription: "two wallpapers share an identifier"
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.schemaVersion, forKey: .version)
        try container.encode(wallpapers, forKey: .wallpapers)
    }
}
