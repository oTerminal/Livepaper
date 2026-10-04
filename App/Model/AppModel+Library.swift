import DesignSystem
import Foundation
import LivepaperCore

// The library window's actions: the grid's selection, favourites, rename,
// delete and its undo, the inspector's edits, the sort order and the playlists.

extension AppModel {
    /// How long an edit rests before it is saved and the displays follow it.
    static let editSettles: Duration = .milliseconds(500)

    // MARK: Selection

    /// The grid changed (section, search, sort, library): the selection stays while the grid shows it.
    func gridDidChange() {
        selection.gridChanged(grid.map(\.id))
    }

    /// The sidebar leaves a display that was unplugged, or a playlist that was deleted, for All.
    func resolveSection() {
        let resolved = section.resolved(displays: displays.map(\.identity), playlists: state.playlists)
        if resolved != section {
            section = resolved
        }
    }

    func select(_ id: WallpaperID) {
        selection.click(id)
    }

    func deselect() {
        selection = GridSelection()
    }

    /// The arrow keys, Home and End. `columns` is how many tiles fit a row.
    func moveSelection(_ move: GridSelection.Move, columns: Int) {
        selection.move(move, in: grid.map(\.id), columns: columns)
    }

    // MARK: Favourite and rename

    func setFavourite(_ isFavourite: Bool, for id: WallpaperID) {
        guard let next = try? library.settingFavourite(isFavourite, for: id) else { return }
        commit(library: next)
    }

    func toggleFavourite(_ id: WallpaperID) {
        guard let wallpaper = library[id] else { return }
        setFavourite(!wallpaper.isFavourite, for: id)
    }

    /// Named as Core names it (`Library.renaming`). Answers false when the name
    /// was refused, such as an empty one, so the field can show the old name again.
    @discardableResult
    func rename(_ id: WallpaperID, to name: String) -> Bool {
        guard let next = try? library.renaming(id, to: name) else { return false }
        return commit(library: next)
    }

    // MARK: Delete and undo

    /// Deletes a wallpaper from the library and from every display, playlist and
    /// recent that names it, at once. "Deleted <name>" offers Undo for the
    /// toast's lifetime; the wallpaper's folder goes to the Trash when it ends.
    func delete(_ id: WallpaperID) {
        // Its toast is about to be replaced: the delete before this one is final.
        if let pending = pendingDeletion {
            finishDeletion(ifStill: pending.toast)
        }
        let deletion: Deletion
        do {
            deletion = try LivepaperCore.deleteWallpaper(id, library: library, state: state)
        } catch {
            return
        }
        // The selection moves on before the grid changes: once the wallpaper has
        // left the grid, the grid's change would clear it instead.
        let selectionBefore = selection
        selection.deleted(id, from: grid.map(\.id))
        do {
            try change(library: deletion.library, state: deletion.state)
        } catch {
            selection = selectionBefore
            return
        }
        drafts[id] = nil
        settling.removeValue(forKey: id)?.cancel()

        let toast = ToastItem(message: deletion.record.toastWords, systemImage: "trash", undoTitle: "Undo")
        pendingDeletion = PendingDeletion(record: deletion.record, toast: toast.id)
        toasts.send(.show(toast))
        AppLog.logger.notice("\(AppLog.deleted(deletion.record.wallpaper), privacy: .public)")
    }

    /// The Delete key.
    func deleteSelected() {
        guard let id = selection.selected else { return }
        delete(id)
    }

    /// The toast host's undo, by the toast's identifier: the wallpaper comes back
    /// where it was, with the app state from before the delete, and is selected.
    func undo(_ toast: ToastItem.ID) {
        guard let pending = pendingDeletion, pending.toast == toast else { return }
        pendingDeletion = nil
        guard let restored = try? LivepaperCore.undoDeletion(pending.record, library: library) else { return }
        commit(library: restored.library, state: restored.state)
        selection.click(pending.record.wallpaper.id)
        AppLog.logger.notice("\(AppLog.undone(pending.record.wallpaper), privacy: .public)")
    }

    /// The undo is gone: the folder goes to the Trash. A quit before this leaves
    /// it for the next launch's sweep.
    func finishDeletion(ifStill toast: ToastItem.ID) {
        guard let pending = pendingDeletion, pending.toast == toast else { return }
        pendingDeletion = nil
        let id = pending.record.wallpaper.id
        do {
            try services.trash(id)
            AppLog.logger.notice("\(AppLog.trashed(id), privacy: .public)")
        } catch {
            AppLog.logger.error("\(AppLog.trashFailed(id, error), privacy: .public)")
        }
    }

    /// The library window closed: its toast goes with it, and a delete's undo too.
    func libraryWindowDidClose() {
        toasts.send(.dismiss)
    }

    // MARK: The inspector's edits

    /// Fit, focal point, pan and zoom. The preview follows at once, the library
    /// and the displays once the edit rests.
    func editPresentation(_ presentation: Presentation, of id: WallpaperID) {
        guard let wallpaper = library[id] else { return }
        drafts[id] = WallpaperDraft(presentation: presentation, volume: volume(of: wallpaper))
        settleLater(id)
    }

    /// One part of the presentation, such as `{ $0.fit = .fit }`.
    func editPresentation(of id: WallpaperID, _ edit: (inout Presentation) -> Void) {
        guard let wallpaper = library[id] else { return }
        var edited = presentation(of: wallpaper)
        edit(&edited)
        editPresentation(edited, of: id)
    }

    /// 0 to 1. Mute is `setMuted`: moving the slider unmutes, as `VolumeSlider` does itself.
    func editVolume(_ volume: Double, of id: WallpaperID) {
        guard let wallpaper = library[id] else { return }
        drafts[id] = WallpaperDraft(presentation: presentation(of: wallpaper), volume: volume)
        settleLater(id)
    }

    private func settleLater(_ id: WallpaperID) {
        settling[id]?.cancel()
        settling[id] = Task {
            do {
                try await Task.sleep(for: Self.editSettles)
            } catch {
                return
            }
            settle(id)
        }
    }

    private func settle(_ id: WallpaperID) {
        settling[id] = nil
        guard let draft = drafts.removeValue(forKey: id),
              let next = try? library.settingPresentation(draft.presentation, for: id).settingVolume(draft.volume, for: id)
        else { return }
        commit(library: next)
    }

    /// Every edit in progress, now: at quit.
    func settleDrafts() {
        for id in Array(drafts.keys) {
            settling[id]?.cancel()
            settle(id)
        }
    }

    // MARK: Sort

    func setSortOrder(_ order: Library.SortOrder) {
        var next = state
        next.sortOrder = order
        commit(state: next)
    }

    // MARK: Playlists

    /// A new playlist, last in the sidebar, as Core makes one
    /// (`AppState.creatingPlaylist(_:named:with:)`); the sidebar goes where Core
    /// says (`LibrarySection.afterCreating`). Nil when the name was refused.
    @discardableResult
    func createPlaylist(named name: String, with wallpapers: [WallpaperID] = []) -> PlaylistID? {
        let id = PlaylistID(uuid: UUID())
        guard let next = try? state.creatingPlaylist(id, named: name, with: wallpapers), let playlist = next[playlist: id],
              commit(state: next) else { return nil }
        section = section.afterCreating(playlist)
        return id
    }

    /// Named as Core names it (`AppState.renamingPlaylist`). Answers false when
    /// the name was refused, so the field can show the old name again.
    @discardableResult
    func renamePlaylist(_ id: PlaylistID, to name: String) -> Bool {
        guard let next = try? state.renamingPlaylist(id, to: name) else { return false }
        return commit(state: next)
    }

    /// Displays that showed it show what All Displays has, or nothing; the sidebar
    /// leaves it for All (`LibrarySection.resolved`).
    func deletePlaylist(_ id: PlaylistID) {
        commit(state: state.deletingPlaylist(id))
    }

    func setInterval(_ interval: Duration, of playlist: PlaylistID) {
        commit(state: state.settingPlaylist(playlist, interval: interval))
    }

    func setShuffle(_ shuffle: Bool, of playlist: PlaylistID) {
        commit(state: state.settingPlaylist(playlist, shuffle: shuffle))
    }

    /// At the end, and once.
    func add(_ wallpaper: WallpaperID, to playlist: PlaylistID) {
        commit(state: state.adding(wallpaper, toPlaylist: playlist))
    }

    func remove(_ wallpaper: WallpaperID, from playlist: PlaylistID) {
        commit(state: state.removing(wallpaper, fromPlaylist: playlist))
    }
}

/// A presentation or volume the inspector is editing.
struct WallpaperDraft: Equatable {
    var presentation: Presentation
    var volume: Double
}

/// A delete whose undo toast is still up. Its folder goes to the Trash when the toast ends.
struct PendingDeletion {
    let record: DeletionRecord
    let toast: ToastItem.ID
}
