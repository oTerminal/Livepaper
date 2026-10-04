import DesignSystem
import Foundation
import LivepaperCore
import LivepaperImport

// What the screens read. Every value is a Core or Import projection of what the
// model keeps, worked out when it is read.

extension AppModel {
    // MARK: The popover

    /// One card per connected display, in the displays' order.
    var nowPlaying: [NowPlaying] {
        LivepaperCore.nowPlaying(
            library: library,
            state: state,
            connected: displays.map(\.identity),
            render: renderState,
            isPausedAll: isPausedAll,
            host: services.host.capabilities,
            now: Date(),
            hasFiles: services.hasFiles
        )
    }

    /// The last wallpapers set on a display, newest first.
    var recents: [Wallpaper] {
        state.recents.compactMap { library[$0] }
    }

    var isMuted: Bool { state.isMuted }

    func display(_ identity: DisplayIdentity) -> Display? {
        displays.first { $0.identity == identity }
    }

    /// The playlist pickers' options, with how many wallpapers each holds.
    var playlistOptions: [PlaylistOption<PlaylistID>] {
        let counts = sidebarCounts.playlists
        return state.playlists.map { PlaylistOption(id: $0.id, title: $0.name, count: counts[$0.id] ?? 0) }
    }

    // The popover's two ways into the library, which the caller then opens.

    /// Choose, on a card whose display shows nothing: the sidebar goes to All,
    /// where a wallpaper is picked and set on the display.
    func chooseWallpaperInLibrary() {
        section = .all
    }

    /// New Playlist… in a card's playlist picker: an empty playlist, which the
    /// sidebar goes to (`createPlaylist`), so the library opens on it to be
    /// filled. The display keeps what it shows: an empty playlist would show nothing.
    func startNewPlaylist() {
        createPlaylist(named: "New Playlist")
    }

    // MARK: The status line

    var statusLine: StatusLineContent {
        LivepaperCore.statusLine(
            host: hostStatus,
            showing: renderState?.displays.count ?? 0,
            isPausedAll: isPausedAll,
            importing: importList.progress,
            restart: serviceRestart.phase
        )
    }

    // MARK: The library window

    var sidebarCounts: SidebarCounts {
        LivepaperCore.sidebarCounts(library: library, state: state)
    }

    /// In the user's order.
    var playlists: [Playlist] { state.playlists }

    /// The section's wallpapers that match the search, in the sort order; a playlist keeps its own.
    var grid: [Wallpaper] {
        libraryGrid(library: library, state: state, section: section, search: search)
    }

    var sortOrder: Library.SortOrder { state.sortOrder }

    var selectedWallpaper: Wallpaper? {
        selection.selected.flatMap { library[$0] }
    }

    /// The playlist the sidebar has selected, for the inspector's playlist row.
    var selectedPlaylist: Playlist? {
        guard case .playlist(let id) = section else { return nil }
        return state[playlist: id]
    }

    /// The playlists a wallpaper is in, for its context menu.
    func playlists(containing wallpaper: WallpaperID) -> [Playlist] {
        state.playlists.filter { $0.wallpapers.contains(wallpaper) }
    }

    // MARK: The inspector

    /// The presentation the inspector and its preview show: the edit in progress, else the saved one.
    func presentation(of wallpaper: Wallpaper) -> Presentation {
        drafts[wallpaper.id]?.presentation ?? wallpaper.presentation
    }

    /// The volume the inspector's slider shows: the edit in progress, else the saved one.
    func volume(of wallpaper: Wallpaper) -> Double {
        drafts[wallpaper.id]?.volume ?? wallpaper.volume
    }

    /// What the inspector's preview plays at: the slider's volume, or silence while muted.
    func previewVolume(of wallpaper: Wallpaper) -> Double {
        var edited = wallpaper
        edited.volume = volume(of: wallpaper)
        return state.playbackVolume(of: edited)
    }

    /// The Set on Display button's targets: the connected displays, each checked
    /// when it shows this one.
    func setOnDisplayTargets(for assignment: Assignment) -> [SetOnDisplayTarget] {
        displays.map { display in
            SetOnDisplayTarget(id: display.targetID, name: display.name, isCurrent: state.shows(assignment, on: display.identity))
        }
    }

    func setOnDisplayState(for assignment: Assignment) -> SetOnDisplayState {
        (setOnDisplayFeedback[assignment]?.phase ?? .idle).setOnDisplayState
    }

    // MARK: Import

    /// A drop, the Import button and Command-O are taken once the launch has swept
    /// what a killed import left, and while the library can be written.
    var canImport: Bool {
        importer != nil && libraryProblem == nil && !isQuitting
    }

    // MARK: Settings

    var pauseRules: PauseRules { state.pauseRules }

    var loginItem: LoginItemStatus { systemServices.loginItem }

    func hotkey(for action: HotkeyAction) -> KeyCombination? {
        systemServices.hotkeys[action]
    }

    /// What already uses a combination, for the recorder's conflict; nil when it is free.
    func hotkeyOwner(of combination: KeyCombination, for action: HotkeyAction) -> String? {
        systemServices.availability(of: combination, for: action).owner
    }

    // MARK: The menu

    var isPlaybackMetricsOn: Bool { services.isPlaybackMetricsOn() }
}

extension AppModel {
    /// Whether `launch()` has run, or a preview stands in for it. A launch that
    /// asks for the drag to Applications never runs it, nor one offering the
    /// move until Not Now, and the model changes and writes nothing then.
    var hasStarted: Bool { launching != nil || isLaunched }

    /// A change before the launch, which only a launch asking where Livepaper runs can make: refused, and said so.
    func refusedBeforeStart() -> LibraryProblem {
        AppLog.logger.error("\(AppLog.notStarted, privacy: .public)")
        return .notStarted
    }
}

/// Why nothing is being written, for the screens to say; a change refused for it throws it.
enum LibraryProblem: Error, Equatable {
    /// `library.json` could not be read: written by a newer Livepaper, or damaged
    /// along with the copy kept before it.
    case unreadable
    /// Thrown only: the launch did not start Livepaper, asking where it runs.
    case notStarted
}
