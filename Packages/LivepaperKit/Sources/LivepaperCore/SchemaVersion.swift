import Foundation

/// The version every persisted file carries.
///
/// A minor version only adds fields, which an older reader ignores and a newer
/// reader defaults. A major version changes meaning: a reader that does not
/// know it refuses the file rather than guess.
public struct SchemaVersion: Codable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int

    public init(major: Int, minor: Int) {
        self.major = major
        self.minor = minor
    }

    public var description: String { "\(major).\(minor)" }

    /// Throws unless a reader of `current` can read a file of this version.
    func requireReadable(by current: SchemaVersion) throws {
        guard major == current.major else { throw SchemaError.unsupportedVersion(self) }
    }
}

public enum SchemaError: Error, Equatable, Sendable {
    /// The file was written by a schema this build does not know. Nothing is read from it.
    case unsupportedVersion(SchemaVersion)
}

/// JSON as Livepaper's files are written: stable key order, so that the same
/// value gives the same bytes.
///
/// Dates are written as `Date` encodes itself, in seconds since 2001. It is
/// the one form that gives back exactly the date that went in, so a value read
/// from disk equals the value that was written.
enum PersistedJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    static func decoder() -> JSONDecoder {
        JSONDecoder()
    }
}
