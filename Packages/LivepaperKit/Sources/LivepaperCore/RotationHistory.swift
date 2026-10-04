/// What one display's playlist showed this session, for Previous. Held in
/// memory and never persisted: a relaunch starts without one.
public struct RotationHistory: Equatable, Sendable {
    /// Oldest first.
    private var left: [WallpaperID] = []

    public init() {}

    /// Called before Next, or a rotation, moves the display away from `wallpaper`.
    /// Previous does not call it, so that pressing Previous again steps further back.
    public mutating func leaving(_ wallpaper: WallpaperID) {
        left.append(wallpaper)
    }

    /// The wallpaper to step back to: the last one left that the playlist still
    /// has and that is not showing, else the one before `current` in the
    /// playlist's order, wrapping. Nil for a playlist of fewer than two.
    public mutating func previous(in playlist: Playlist, current: WallpaperID?) -> WallpaperID? {
        let wallpapers = playlist.wallpapers
        guard wallpapers.count >= 2 else { return nil }
        while let last = left.popLast() {
            if last != current, wallpapers.contains(last) { return last }
        }
        guard let current, let index = wallpapers.firstIndex(of: current) else { return wallpapers.last }
        return wallpapers[(index + wallpapers.count - 1) % wallpapers.count]
    }
}

import Foundation

/// Next and Previous over the app state, with each display's `RotationHistory`
/// kept for the session. The model commits what they answer and tells
/// `forget(changedFrom:to:)` of every change.
public struct RotationHistories: Equatable, Sendable {
    private var byDisplay: [DisplayIdentity: RotationHistory] = [:]

    public init() {}

    /// The playlist the display shows moves on at once, and what it showed is
    /// kept for Previous. A display showing a wallpaper, or nothing, is left as it is.
    public mutating func next(
        on display: DisplayIdentity, in state: AppState, library: Library, now: Date, rng: inout some RandomNumberGenerator
    ) -> AppState {
        let after = state.rotating(display, .next(at: now), rng: &rng)
        if let left = state.wallpaper(shownOn: display, in: library)?.id, after.wallpaper(shownOn: display, in: library)?.id != left {
            byDisplay[display, default: RotationHistory()].leaving(left)
        }
        return after
    }

    /// A rotation the user did not ask for, the rotation driver's tick, wake or
    /// login: each display whose playlist moved on keeps what it showed, as Next does.
    public mutating func rotated(from before: AppState, to after: AppState, library: Library) {
        for display in after.rotation.keys where before.assignment(for: display) == after.assignment(for: display) {
            guard let left = before.wallpaper(shownOn: display, in: library)?.id,
                  after.wallpaper(shownOn: display, in: library)?.id != left else { continue }
            byDisplay[display, default: RotationHistory()].leaving(left)
        }
    }

    /// Back through what the display's playlist showed this session, then back
    /// through the playlist's order. The state as it was when there is nowhere to go.
    public mutating func previous(on display: DisplayIdentity, in state: AppState, library: Library) -> AppState {
        guard case .playlist(let id)? = state.assignment(for: display), let playlist = state[playlist: id] else { return state }
        let showing = state.wallpaper(shownOn: display, in: library)?.id
        guard let back = byDisplay[display, default: RotationHistory()].previous(in: playlist, current: showing) else { return state }
        return state.steppingBack(display, to: back)
    }

    /// A display that now shows anything else starts again: its history was of another playlist.
    public mutating func forget(changedFrom before: AppState, to after: AppState) {
        for display in byDisplay.keys where before.assignment(for: display) != after.assignment(for: display) {
            byDisplay[display] = nil
        }
    }
}
