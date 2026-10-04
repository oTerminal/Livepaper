import Foundation

public enum SceneReadError: Error, Equatable, Sendable {
    /// Not a Wallpaper Engine package, or one cut short.
    case notAPackage
    /// The package has no file of this name.
    case missingEntry(String)
    /// The scene's JSON, or a file it leads to, cannot be read.
    case malformedScene
}

/// A Wallpaper Engine package (`scene.pkg`): the scene's JSON, materials,
/// models, textures and shaders in one file.
///
///     u32 length, "PKGV00xx"
///     u32 count; per entry: u32 name length, name, u32 offset, u32 size
///     the entries back to back, their offsets counted from the end of the table
///
/// The file is mapped, not read: a package can be hundreds of megabytes, and
/// an import reads a few kilobytes of it.
public struct ScenePackage: Sendable {
    /// "PKGV0018", say. Every version seen has the same layout.
    public let version: String
    /// Entry names, in the package's own order.
    public let names: [String]
    private let entries: [String: Range<Int>]
    private let data: Data

    public init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url, options: .alwaysMapped))
    }

    public init(data: Data) throws(SceneReadError) {
        do {
            var reader = ByteReader(data)
            let version = try reader.lengthPrefixedString()
            guard version.hasPrefix("PKGV"), version.count == 8 else { throw SceneReadError.notAPackage }
            let count = Int(try reader.u32())
            // Each entry takes at least twelve bytes of table, which bounds a count that lies.
            guard count <= (data.count - (reader.offset - data.startIndex)) / 12 else { throw SceneReadError.notAPackage }
            var table: [TableEntry] = []
            for _ in 0..<count {
                let name = try reader.lengthPrefixedString()
                table.append(TableEntry(name: name, offset: Int(try reader.u32()), size: Int(try reader.u32())))
            }
            let base = reader.offset
            var entries: [String: Range<Int>] = [:]
            for entry in table {
                let start = base + entry.offset
                guard start <= data.endIndex, entry.size <= data.endIndex - start else { throw SceneReadError.notAPackage }
                entries[entry.name] = start..<start + entry.size
            }
            self.version = version
            names = table.map(\.name)
            self.entries = entries
            self.data = data
        } catch let error as SceneReadError {
            throw error
        } catch {
            throw .notAPackage
        }
    }

    private struct TableEntry {
        var name: String
        var offset: Int
        var size: Int
    }

    /// The entry's bytes, or nil when the package has none of that name.
    public func entry(_ name: String) -> Data? {
        entries[name].map { data[$0] }
    }

    /// The entry's bytes, or `SceneReadError.missingEntry`.
    public func require(_ name: String) throws(SceneReadError) -> Data {
        guard let entry = entry(name) else { throw .missingEntry(name) }
        return entry
    }
}
