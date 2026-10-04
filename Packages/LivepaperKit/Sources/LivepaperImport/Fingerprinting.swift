import CryptoKit
import Foundation
import LivepaperCore

/// The SHA-256 of a source file, taken before any conversion, so that a file
/// that is already in the library ends the import before anything is written.
@concurrent
public func fingerprint(of url: URL, chunkSize: Int = 4 << 20) async throws -> Fingerprint {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }

    var hash = SHA256()
    while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
        try Task.checkCancellation()
        hash.update(data: chunk)
    }
    return Fingerprint(sha256: hash.finalize().map { String(format: "%02x", $0) }.joined())
}
