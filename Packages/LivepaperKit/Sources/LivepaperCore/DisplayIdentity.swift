import Foundation

/// A physical display, identified by the UUID macOS assigns to it.
///
/// The UUID survives unplugging, replugging and reordering, unlike a screen's
/// index or its `CGDirectDisplayID`, so assignments keyed by it are remembered
/// while a display is disconnected.
public struct DisplayIdentity: Hashable, Codable, Sendable, CustomStringConvertible {
    public let uuid: UUID

    public init(uuid: UUID) {
        self.uuid = uuid
    }

    // Persisted as a bare UUID string.
    public init(from decoder: any Decoder) throws {
        uuid = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(uuid)
    }

    public var description: String { uuid.uuidString }
}
