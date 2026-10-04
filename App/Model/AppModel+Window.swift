import AppKit
import LivepaperCore

// What the library window reads beyond the grid itself. The fakes run's commands
// for the window are in App/Shell/FakesCommands.swift.

extension AppModel {
    /// Why the grid shows nothing; nil while it shows a wallpaper.
    var emptyGrid: EmptyGrid? {
        LivepaperCore.emptyGrid(library: library, state: state, section: section, search: search)
    }

    /// The frame the inspector's preview and the pan and zoom editor show: the
    /// first connected display's shape, else 16:10.
    var previewAspectRatio: CGFloat {
        displays.first?.aspectRatio ?? 16.0 / 10
    }
}

extension NSWindow {
    /// The library window's scene (`AppWindows.libraryID`): SwiftUI gives its
    /// window the scene's identifier ("library", seen on macOS 27).
    var isLibraryWindow: Bool {
        identifier?.rawValue.hasPrefix(AppWindows.libraryID) ?? false
    }
}
