import Foundation

public enum LibraryPathError: Error, Equatable, Sendable {
    case empty
    case absolute
    /// A step of the path that is not a plain name.
    case illegalComponent(String)
}

/// A path relative to the library root that is known to stay inside it.
///
/// The extension may read the library and nothing else, so the
/// paths that reach it are held to the names the library itself writes: steps
/// of ASCII letters, digits, `.`, `-` and `_`, none starting with a dot. That
/// leaves no room for parent steps, absolute paths, lookalike characters or
/// anything that reads like a link. A manifest or render state that names
/// anything else does not decode.
///
/// It is a check of the name only. Core does not touch the file system, so a
/// caller that must rule out a real symlink resolves it and asks
/// `LibraryLocation.contains` again.
public struct LibraryPath: Hashable, Codable, Sendable, CustomStringConvertible {
    public let relative: String

    public init(_ relative: String) throws {
        guard !relative.isEmpty else { throw LibraryPathError.empty }
        guard !relative.hasPrefix("/") else { throw LibraryPathError.absolute }
        for component in relative.split(separator: "/", omittingEmptySubsequences: false) where !Self.isPlainName(component) {
            throw LibraryPathError.illegalComponent(String(component))
        }
        self.relative = relative
    }

    // Persisted as a bare string, and checked again on the way in.
    public init(from decoder: any Decoder) throws {
        try self.init(try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(relative)
    }

    public var description: String { relative }

    private static func isPlainName(_ component: Substring) -> Bool {
        guard let first = component.unicodeScalars.first, first != "." else { return false }
        return component.unicodeScalars.allSatisfy { scalar in
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9", ".", "-", "_": true
            default: false
            }
        }
    }
}

/// Where the library is on disk.
///
/// The home folder is the caller's to supply. Inside the extension's sandbox
/// the home-directory APIs return the container, so nothing in Core calls them.
public struct LibraryLocation: Equatable, Sendable {
    public let root: URL

    public init(home: URL) {
        let library = home.appending(path: "Library/Application Support/Livepaper", directoryHint: .isDirectory)
        root = URL(filePath: "/" + Self.normalised(library).joined(separator: "/"), directoryHint: .isDirectory)
    }

    /// The versioned manifest of the library, written by the app only.
    public var manifest: URL { root.appending(path: "library.json", directoryHint: .notDirectory) }

    /// What the extension is to show, replaced atomically by the app.
    public var renderState: URL { root.appending(path: "render-state.json", directoryHint: .notDirectory) }

    /// Assignments, playlists and the rest of what the user chose, written by the app only.
    public var appState: URL { root.appending(path: "app-state.json", directoryHint: .notDirectory) }

    /// One folder per wallpaper, named by its identifier.
    public var wallpapers: URL { root.appending(path: "wallpapers", directoryHint: .isDirectory) }

    /// Where an import is built, on the same volume, so that committing it is a rename.
    public var staging: URL { root.appending(path: ".staging", directoryHint: .isDirectory) }

    /// The wallpaper store as it was before Livepaper was selected, kept so that
    /// leaving can put back what it named, an Aerial included.
    public var keptWallpaperStore: URL {
        root.appending(path: "wallpaper-store-before-livepaper.plist", directoryHint: .notDirectory)
    }

    /// The app's command socket, which the `livepaper` tool talks to.
    public var commandSocket: URL { root.appending(path: "command.sock", directoryHint: .notDirectory) }

    public func url(for path: LibraryPath) -> URL {
        root.appending(path: path.relative, directoryHint: .notDirectory)
    }

    /// Turns an unchecked relative path into a URL inside the library, or throws `LibraryPathError`.
    public func resolve(_ relative: String) throws -> URL {
        url(for: try LibraryPath(relative))
    }

    /// Whether a URL, once `.` and `..` are worked out, is the root or inside it.
    public func contains(_ url: URL) -> Bool {
        Self.normalised(url).starts(with: Self.normalised(root))
    }

    /// The path's steps with `.` and `..` worked out by name alone. Foundation's
    /// own standardising looks at the disk (it drops `/private` when the rest
    /// exists), so the answer would depend on what happens to be there.
    private static func normalised(_ url: URL) -> [String] {
        var steps: [String] = []
        for component in url.pathComponents where component != "/" && component != "." {
            if component == ".." {
                _ = steps.popLast()
            } else {
                steps.append(component)
            }
        }
        return steps
    }
}
