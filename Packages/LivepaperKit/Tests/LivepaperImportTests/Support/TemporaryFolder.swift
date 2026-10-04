import Foundation

/// A folder of the test's own under the temporary directory, removed when the test lets go of it.
final class TemporaryFolder: Sendable {
    let url: URL

    init() throws {
        // The real path, so that paths compare equal to what the file system reports (/var is a link to
        // /private/var, and Foundation's own resolving drops the /private again).
        let temporary = FileManager.default.temporaryDirectory.path
        let real = realpath(temporary, nil).map { pointer in
            defer { free(pointer) }
            return String(cString: pointer)
        }
        url = URL(filePath: real ?? temporary, directoryHint: .isDirectory)
            .appending(path: "LivepaperImportTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// Writes a file, making the folders on the way to it.
    @discardableResult
    func write(_ contents: String = "", to path: String) throws -> URL {
        let file = url.appending(path: path, directoryHint: .notDirectory)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: file)
        return file
    }

    func folder(_ path: String) -> URL {
        url.appending(path: path, directoryHint: .isDirectory)
    }

    func file(_ path: String) -> URL {
        url.appending(path: path, directoryHint: .notDirectory)
    }
}
