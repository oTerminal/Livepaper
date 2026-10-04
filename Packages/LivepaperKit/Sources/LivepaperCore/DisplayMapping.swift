/// The choice of which wallpaper, or which playlist, a display shows.
public enum Assignment: Hashable, Sendable {
    case wallpaper(WallpaperID)
    case playlist(PlaylistID)
}

// Persisted as the one thing it names, `{"wallpaper": "<UUID>"}` or
// `{"playlist": "<UUID>"}`: an assignment naming both or neither does not decode.
extension Assignment: Codable {
    private enum CodingKeys: String, CodingKey {
        case wallpaper, playlist
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let wallpaper = try container.decodeIfPresent(WallpaperID.self, forKey: .wallpaper)
        let playlist = try container.decodeIfPresent(PlaylistID.self, forKey: .playlist)
        switch (wallpaper, playlist) {
        case (let wallpaper?, nil): self = .wallpaper(wallpaper)
        case (nil, let playlist?): self = .playlist(playlist)
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "an assignment names one wallpaper or one playlist")
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .wallpaper(let id): try container.encode(id, forKey: .wallpaper)
        case .playlist(let id): try container.encode(id, forKey: .playlist)
        }
    }
}

/// What each connected display shows.
///
/// A display keeps its saved assignment while it is unplugged, because `saved`
/// is never pruned here: an absent display is only left out of the result. A
/// display seen for the first time takes "apply to all", or nothing.
public func resolveAssignments(
    _ saved: [DisplayIdentity: Assignment], connected: [DisplayIdentity], applyToAll: Assignment?
) -> [DisplayIdentity: Assignment] {
    var shown: [DisplayIdentity: Assignment] = [:]
    for display in connected {
        shown[display] = saved[display] ?? applyToAll
    }
    return shown
}
