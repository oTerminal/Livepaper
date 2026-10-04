import Foundation

/// Where the library is kept between launches. Only the app writes it.
public protocol LibraryStore: Sendable {
    func load() throws -> Library
    func save(_ library: Library) throws
}

/// The library as a versioned JSON manifest, replaced atomically.
///
/// The manifest before the current one is kept beside it. A manifest that
/// cannot be read (cut short by a power loss, say) loads that one instead, and
/// when neither can be read `load` throws: it never answers with an empty
/// library, which the next save would make permanent.
public struct FileLibraryStore: LibraryStore {
    public let manifest: URL

    /// The last manifest that was known to be good when it was replaced.
    var previous: URL {
        manifest.deletingPathExtension().appendingPathExtension("previous.json")
    }

    public init(manifest: URL) {
        self.manifest = manifest
    }

    public func load() throws -> Library {
        let files = FileManager.default
        guard files.fileExists(atPath: manifest.path) else {
            return files.fileExists(atPath: previous.path) ? try read(previous) : Library()
        }
        do {
            return try read(manifest)
        } catch let error as SchemaError {
            // Written by a newer Livepaper. Falling back would quietly undo what it did.
            throw error
        } catch {
            guard let lastGood = try? read(previous) else { throw error }
            return lastGood
        }
    }

    public func save(_ library: Library) throws {
        let data = try library.encode()
        try FileManager.default.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Only a manifest that still reads becomes the fallback. A damaged one
        // must not push out the good one that is already there.
        if let current = try? Data(contentsOf: manifest), (try? Library.decode(current)) != nil {
            try current.write(to: previous, options: .atomic)
        }
        try data.write(to: manifest, options: .atomic)
    }

    private func read(_ url: URL) throws -> Library {
        try Library.decode(Data(contentsOf: url))
    }
}
