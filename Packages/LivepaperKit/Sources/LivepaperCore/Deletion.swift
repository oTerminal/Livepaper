/// All that undo needs: the removal, and the app state from before the delete.
///
/// The app state is kept whole rather than worked back, so that undo puts the
/// wallpaper back on every display, playlist and rotation it was on.
public struct DeletionRecord: Equatable, Sendable {
    public let removal: Library.Removal
    public let priorState: AppState

    public var wallpaper: Wallpaper { removal.wallpaper }

    /// The undo toast's message.
    public var toastWords: String { "Deleted “\(wallpaper.name)”" }
}

/// A delete's outcome: the library and app state without the wallpaper, and the record undo takes.
public struct Deletion: Equatable, Sendable {
    public let library: Library
    public let state: AppState
    public let record: DeletionRecord
}

/// Deletes a wallpaper from the library and from everything in the app state that names it.
public func deleteWallpaper(_ id: WallpaperID, library: Library, state: AppState) throws -> Deletion {
    let (without, removal) = try library.deleting(id)
    return Deletion(library: without, state: state.removingWallpaper(id), record: DeletionRecord(removal: removal, priorState: state))
}

/// Undo: the wallpaper goes back where it was, and the app state is the one from before the delete.
public func undoDeletion(_ record: DeletionRecord, library: Library) throws -> (library: Library, state: AppState) {
    (try library.restoring(record.removal), record.priorState)
}
