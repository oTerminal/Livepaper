import Foundation

/// Where the app state is kept between launches. Only the app writes it.
public protocol AppStateStore: Sendable {
    func load() -> AppStateLoad
    func save(_ state: AppState) throws
}

public enum AppStateLoad: Equatable, Sendable {
    case loaded(AppState)
    /// No file yet: a first launch.
    case missing
    /// The file could not be read, and was moved to this URL so that nothing
    /// overwrites it; the app starts on defaults. The version is the unknown
    /// one it was written with, or nil when the file is damaged.
    case keptAside(URL, SchemaVersion?)
}

/// The app state as a versioned JSON file, replaced atomically.
///
/// Unlike the library, nothing falls back to an older copy: losing the
/// assignments costs a few clicks, while guessing at a file a newer Livepaper
/// wrote could undo what it did. A file this build cannot read is kept aside
/// for that newer build, and the app starts on defaults.
public struct FileAppStateStore: AppStateStore {
    public let file: URL

    public init(file: URL) {
        self.file = file
    }

    /// Where a file this build cannot read is moved, replacing one moved there before.
    public var keptAside: URL {
        file.deletingPathExtension().appendingPathExtension("kept-aside.json")
    }

    public func load() -> AppStateLoad {
        guard let data = try? Data(contentsOf: file) else {
            return FileManager.default.fileExists(atPath: file.path) ? keepAside(version: nil) : .missing
        }
        do {
            return .loaded(try AppState.decode(data))
        } catch SchemaError.unsupportedVersion(let version) {
            return keepAside(version: version)
        } catch {
            return keepAside(version: nil)
        }
    }

    public func save(_ state: AppState) throws {
        let data = try state.encode()
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
    }

    // A move within the folder the save writes to: if it fails, so does the
    // save, and the file is never overwritten either way.
    private func keepAside(version: SchemaVersion?) -> AppStateLoad {
        let files = FileManager.default
        try? files.removeItem(at: keptAside)
        do {
            try files.moveItem(at: file, to: keptAside)
            return .keptAside(keptAside, version)
        } catch {
            return .keptAside(file, version)
        }
    }
}
