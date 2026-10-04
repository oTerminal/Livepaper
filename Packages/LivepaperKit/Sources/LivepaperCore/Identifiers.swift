import Foundation

/// Identifies a wallpaper in the library. It is also the name of the wallpaper's folder.
public struct WallpaperID: Hashable, Codable, Sendable, CustomStringConvertible {
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

/// Identifies a playlist.
public struct PlaylistID: Hashable, Codable, Sendable, CustomStringConvertible {
    public let uuid: UUID

    public init(uuid: UUID) {
        self.uuid = uuid
    }

    public init(from decoder: any Decoder) throws {
        uuid = try decoder.singleValueContainer().decode(UUID.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(uuid)
    }

    public var description: String { uuid.uuidString }
}
