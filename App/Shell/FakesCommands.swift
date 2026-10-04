import AppKit
import DesignSystem
import Foundation
import LivepaperCore

/// The fakes run's commands for the library window, from the fakes remote,
/// so the manual script and the PR's media can drive the window where nothing can
/// click it. Each goes through the model's actions as the window's controls do.
///
///     select Harbour at Dusk | deselect | section Favourites | search harbour | sort name (or newest, oldest)
///     set Studio Display | set All Displays | favourite | delete | undo | fit stretch | volume 0.6
///     new playlist Night Shift | import | cancel panel | size 1180 1100
///     door link livepaper://next | door socket livepaper://status (`Doors.performFake`)
struct FakesCommands {
    let model: AppModel
    let doors: Doors

    /// Answers whether it was one of these.
    func perform(_ verb: String, _ rest: String) -> Bool {
        if verb == "door" { return doors.performFake(rest) }
        return browsing(verb, rest) ?? wallpaper(verb, rest) ?? edit(verb, rest) ?? window(verb, rest) ?? false
    }

    /// Nil when the verb is not one of these; false when what it names is not there.
    private func browsing(_ verb: String, _ rest: String) -> Bool? {
        switch verb {
        case "select":
            guard let wallpaper = model.library.wallpapers.first(where: { $0.name == rest }) else { return false }
            model.select(wallpaper.id)
        case "deselect":
            model.deselect()
        case "section":
            guard let section = section(named: rest) else { return false }
            model.section = section
        case "search":
            model.search = rest
        case "sort":
            let orders: [String: Library.SortOrder] = ["newest": .newestFirst, "oldest": .oldestFirst, "name": .name]
            guard let order = orders[rest] else { return false }
            model.setSortOrder(order)
        default:
            return nil
        }
        return true
    }

    private func wallpaper(_ verb: String, _ rest: String) -> Bool? {
        switch verb {
        case "set":
            let assignment = model.selectedWallpaper.map { Assignment.wallpaper($0.id) } ?? model.selectedPlaylist.map { .playlist($0.id) }
            let target = rest == "All Displays" ? SetOnDisplayTarget.allID : model.displays.first { $0.name == rest }?.targetID
            guard let assignment, let target else { return false }
            model.setOnDisplay(assignment, target: target)
        case "favourite":
            guard let id = model.selection.selected else { return false }
            model.toggleFavourite(id)
        case "delete":
            model.deleteSelected()
        case "undo":
            // As the toast's Undo does it.
            guard case .undo(let toast) = model.toasts.send(.undo) else { return false }
            model.undo(toast)
        default:
            return nil
        }
        return true
    }

    /// The inspector's edits, as its controls make them.
    private func edit(_ verb: String, _ rest: String) -> Bool? {
        guard ["fit", "volume"].contains(verb) else { return nil }
        guard let id = model.selection.selected else { return false }
        if let fit = FitMode(rawValue: rest) {
            model.editPresentation(of: id) { $0.fit = fit }
        } else if let volume = Double(rest) {
            model.editVolume(volume, of: id)
        } else {
            return false
        }
        return true
    }

    private func window(_ verb: String, _ rest: String) -> Bool? {
        switch (verb, rest) {
        case ("new", let name) where name.hasPrefix("playlist "):
            model.createPlaylist(named: String(name.dropFirst("playlist ".count)), with: model.selection.selected.map { [$0] } ?? [])
        case ("import", _):
            model.chooseFilesToImport()
        case ("cancel", "panel"):
            // The Open panel, as a sheet or on its own, chosen with nothing.
            for panel in NSApp.windows.compactMap({ $0 as? NSOpenPanel }) {
                panel.cancel(nil)
            }
        case ("size", let size):
            // The library window's content size, "1180 1100", for looking at a long inspector.
            let points = size.split(separator: " ").compactMap { Double($0) }
            guard points.count == 2, let window = NSApp.windows.first(where: \.isLibraryWindow) else { return false }
            window.setContentSize(CGSize(width: points[0], height: points[1]))
        default:
            return nil
        }
        return true
    }

    /// "All Wallpapers", "Favourites", a playlist's name or a display's.
    private func section(named name: String) -> LibrarySection? {
        switch name {
        case "All Wallpapers": return .all
        case "Favourites": return .favourites
        default:
            if let playlist = model.playlists.first(where: { $0.name == name }) { return .playlist(playlist.id) }
            return model.displays.first { $0.name == name }.map { .nowPlaying($0.identity) }
        }
    }
}
