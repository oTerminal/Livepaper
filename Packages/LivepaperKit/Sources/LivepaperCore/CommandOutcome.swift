import Foundation

/// Why the app does not run a command a door sent it: what the command names
/// is not there, or nothing can be changed now. The app logs `reason`,
/// and the socket replies with it.
public enum CommandRefusal: Error, Hashable, Sendable, CustomStringConvertible {
    case noSuchWallpaper(WallpaperID)
    case noSuchPlaylist(PlaylistID)
    /// A display that is not connected now.
    case notConnected(DisplayIdentity)
    /// `next` names displays none of which shows a playlist.
    case noPlaylistShown(DisplayTarget)
    /// Nothing is written while the library could not be read.
    case libraryUnreadable
    case quitting
    /// The launch has not read the library and the displays within the wait, so
    /// the tool is answered rather than left waiting.
    case stillStarting

    public var reason: String {
        switch self {
        case .noSuchWallpaper(let id): "The library has no wallpaper \(id)"
        case .noSuchPlaylist(let id): "There is no playlist \(id)"
        case .notConnected(let display): "Display \(display) is not connected"
        case .noPlaylistShown(.all): "No display shows a playlist"
        case .noPlaylistShown(.display(let display)): "Display \(display) does not show a playlist"
        case .libraryUnreadable: "The library could not be read, so Livepaper changes nothing"
        case .quitting: "Livepaper is quitting"
        case .stillStarting: "Livepaper is still starting; try again in a moment"
        }
    }

    public var description: String { reason }
}

extension CommandReply {
    public static func refused(_ refusal: CommandRefusal) -> CommandReply {
        .refused(reason: refusal.reason)
    }
}

// MARK: - What a command acts on

extension DisplayTarget {
    /// The connected displays this names, in their order: every one for `all`,
    /// else the one it names, which must be connected.
    public func displays(connected: [DisplayIdentity]) throws(CommandRefusal) -> [DisplayIdentity] {
        switch self {
        case .all: return connected
        case .display(let display):
            guard connected.contains(display) else { throw .notConnected(display) }
            return [display]
        }
    }
}

extension AppState {
    /// Throws unless the library holds the wallpaper, or this state the
    /// playlist: a command names only what is there.
    public func checking(_ assignment: Assignment, in library: Library) throws(CommandRefusal) {
        switch assignment {
        case .wallpaper(let id): guard library[id] != nil else { throw .noSuchWallpaper(id) }
        case .playlist(let id): guard self[playlist: id] != nil else { throw .noSuchPlaylist(id) }
        }
    }

    /// `next`: the displays among those named that show a playlist, in the
    /// connected displays' order, paused or not (Next works on a paused
    /// display and leaves it paused). Refused when none does.
    public func displaysMovingOn(_ target: DisplayTarget, connected: [DisplayIdentity]) throws(CommandRefusal) -> [DisplayIdentity] {
        let moving = try target.displays(connected: connected).filter { display in
            guard case .playlist(let id)? = assignment(for: display) else { return false }
            return self[playlist: id] != nil
        }
        guard !moving.isEmpty else { throw .noPlaylistShown(target) }
        return moving
    }
}

// MARK: - Replies

extension CommandReply {
    /// `next`'s reply: what each display it moved on shows now, by the
    /// display's name and the wallpaper's; nil when the display shows none.
    public static func movedOn(_ displays: [(display: String, wallpaper: String?)]) -> CommandReply {
        .done(message: displays.map { display, wallpaper in
            wallpaper.map { "\(display) now shows “\($0)”." } ?? "\(display) moved on."
        }.joined(separator: "\n"))
    }
}
