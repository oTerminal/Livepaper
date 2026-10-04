extension AppState {
    /// How loud a wallpaper plays, on a display or in the inspector's preview:
    /// mute is the app's, so muted it is silent whatever its own volume.
    public func playbackVolume(of wallpaper: Wallpaper) -> Double {
        isMuted ? 0 : wallpaper.volume
    }

    /// The wallpaper a display shows: its assignment's, or its playlist's
    /// rotation. A wallpaper the library has lost counts as nothing.
    public func wallpaper(shownOn display: DisplayIdentity, in library: Library) -> Wallpaper? {
        switch assignment(for: display) {
        case .wallpaper(let id)?:
            return library[id]
        case .playlist(let id)?:
            guard let playlist = self[playlist: id] else { return nil }
            let rotation = rotation[display] ?? RotationState()
            return rotation.showing(in: playlist) { library[$0] != nil }.flatMap { library[$0] }
        case nil:
            return nil
        }
    }
}

extension RenderState {
    /// The render state for this library and app state on the connected
    /// displays, applied on every change. Each display's assignment is
    /// `resolveAssignments`', through `AppState.assignment(for:)`.
    ///
    /// A display that shows nothing is left out, so the extension shows nothing
    /// there. Mute is the app's: every volume is 0 and the extension leaves the
    /// audio track unopened. The generation continues `previous`'s, and the
    /// answer is nil when it would say nothing `previous` does not. With no
    /// previous state it is generation 1 even when nothing is shown, so that the
    /// extension learns it should show nothing. A stopped previous state, the one
    /// Quit leaves, is followed by a live one.
    ///
    /// Pause All pauses every display in place, as a display's own pause does:
    /// the extension holds each one's current picture and keeps its decoder, so
    /// Resume All, a state made without it, is instant and leaves a display's
    /// own pause as it was. It is the app's while it runs, never remembered.
    public static func make(
        library: Library,
        state: AppState,
        connected: [DisplayIdentity],
        conditions: SensedConditions?,
        isPausedAll: Bool = false,
        previous: RenderState?
    ) -> RenderState? {
        let displays = Set(connected).sorted(byDisplay: \.self).compactMap { identity -> Display? in
            guard let wallpaper = state.wallpaper(shownOn: identity, in: library) else { return nil }
            return Display(
                identity: identity,
                wallpaper: wallpaper.id,
                optimisedCopy: wallpaper.optimisedCopy,
                poster: wallpaper.poster,
                presentation: wallpaper.presentation,
                volume: state.playbackVolume(of: wallpaper),
                userPaused: isPausedAll || state.pausedDisplays.contains(identity),
                scene: wallpaper.scene
            )
        }
        guard let previous else {
            return RenderState(displays: displays, pauseRules: state.pauseRules, conditions: conditions)
        }
        let unchanged = !previous.isStopped
            && previous.displays == displays
            && previous.pauseRules == state.pauseRules
            && previous.conditions == conditions
        if unchanged { return nil }
        return previous.next { next in
            next.isStopped = false
            next.displays = displays
            next.pauseRules = state.pauseRules
            next.conditions = conditions
        }
    }
}
