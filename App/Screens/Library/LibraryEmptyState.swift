import DesignSystem
import LivepaperCore
import SwiftUI

/// What the grid's place shows when it has nothing (`emptyGrid`), each with the way on.
struct LibraryEmptyState: View {
    @Environment(AppModel.self) private var model
    let reason: EmptyGrid

    var body: some View {
        switch reason {
        case .noWallpapers:
            EmptyState(
                title: "No wallpapers yet",
                message: "Drop files or a Wallpaper Engine folder here to import them, or choose them.",
                systemImage: "photo.on.rectangle.angled",
                actionTitle: "Import…",
                action: { model.chooseFilesToImport() }
            )
            .disabled(!model.canImport)
        case .noFavourites:
            EmptyState(
                title: "No favourites",
                message: "Choose Favourite in a wallpaper’s menu, or its heart in the inspector, to find it here.",
                systemImage: "heart"
            )
        case .emptyPlaylist(let id):
            EmptyState(
                title: "No wallpapers in “\(model.playlists.first { $0.id == id }?.name ?? "this playlist")”",
                message: "To put one in, Control-click it in All Wallpapers and choose this playlist under Playlists.",
                systemImage: "rectangle.stack",
                secondaryActionTitle: "Show All Wallpapers",
                secondaryAction: { model.section = .all }
            )
        case .nothingOnDisplay(let identity):
            let name = model.display(identity)?.name ?? "this display"
            EmptyState(
                title: "No wallpaper",
                message: "Nothing is set on \(name) yet.",
                systemImage: "display",
                actionTitle: "Choose a Wallpaper",
                action: { model.section = .all }
            )
        case .noResults(let search):
            EmptyState(
                title: "No results for “\(search)”",
                message: "Check the spelling, or search for something else.",
                systemImage: "magnifyingglass"
            )
        }
    }
}

/// When `library.json` could not be read, nothing is written, so there is nothing to show or change.
struct LibraryProblemState: View {
    var body: some View {
        EmptyState(
            title: "The library could not be read",
            message: "A newer Livepaper may have written it, or it is damaged. Livepaper leaves it as it is and changes nothing.",
            systemImage: "exclamationmark.triangle"
        )
    }
}

#Preview("Empty library") {
    LibraryEmptyState(reason: .noWallpapers)
        .frame(width: 640, height: 420)
        .environment(AppModel.preview(.empty))
}

#Preview("No favourites") {
    LibraryEmptyState(reason: .noFavourites)
        .frame(width: 640, height: 420)
        .environment(AppModel.preview())
}

#Preview("Empty playlist") {
    let model = AppModel.preview()
    LibraryEmptyState(reason: .emptyPlaylist(model.playlists[0].id))
        .frame(width: 640, height: 420)
        .environment(model)
}

#Preview("No wallpaper on a display") {
    let model = AppModel.preview()
    LibraryEmptyState(reason: .nothingOnDisplay(model.displays[1].identity))
        .frame(width: 640, height: 420)
        .environment(model)
}

#Preview("No results") {
    LibraryEmptyState(reason: .noResults(search: "harbour"))
        .frame(width: 640, height: 420)
        .environment(AppModel.preview())
}

#Preview("Library not read") {
    LibraryProblemState()
        .frame(width: 640, height: 420)
}
