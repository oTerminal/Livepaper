import Foundation
import LivepaperCore

// The model's side of the system services: the hotkeys and the login
// item's intent are kept in `app-state.json`, which only the model writes;
// Next Wallpaper's hotkey moves every playlist on; and the pane is where a
// user who picked another wallpaper by hand chooses Livepaper again.

extension AppModel: SystemServicesOwner {
    func keep(hotkeys: [HotkeyAction: KeyCombination]) {
        var next = state
        next.hotkeys = hotkeys
        commit(state: next)
    }

    func keep(loginItemIntent: LoginItemIntent) {
        var next = state
        next.loginItemIntent = loginItemIntent
        commit(state: next)
    }

    /// Next Wallpaper's hotkey: every display that shows a playlist moves on,
    /// in one change. A display showing one wallpaper is left as it is.
    func nextOnEveryPlaylist() {
        let playlists = nowPlaying.filter(\.canSkip).map(\.display)
        guard !playlists.isEmpty else { return }
        var rng = SystemRandomNumberGenerator()
        let now = Date()
        var next = state
        for display in playlists {
            next = histories.next(on: display, in: next, library: library, now: now, rng: &rng)
        }
        commit(state: next)
    }

    /// Whether the popover's status line says Livepaper is not the wallpaper, and
    /// offers the pane: an import running takes the line first.
    var offersWallpaperPane: Bool {
        statusLineOffersWallpaperPane(host: hostStatus, importing: importList.progress, restart: serviceRestart.phase)
    }

    /// System Settings at Wallpaper, for the user to choose "Livepaper": the
    /// popover's line when another wallpaper was picked by hand, and onboarding's
    /// last card once it has sent the user there. Nothing in the store is touched.
    func openWallpaperPane() {
        _ = services.system.wallpaperPane.openWallpaperPane()
    }
}
