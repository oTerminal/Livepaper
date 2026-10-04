import AppKit

/// Opens System Settings at Wallpaper, where the user's click is the fallback for anything the
/// store edit cannot do. Injected, so that tests open nothing.
public protocol WallpaperPaneOpening: AnyObject {
    /// False when System Settings could not be opened.
    func openWallpaperPane() -> Bool
}

/// Opens the pane by its URL. Nothing in it is driven: that would need Accessibility, and an
/// Apple event to System Settings costs an Automation prompt.
public final class WallpaperPane: WallpaperPaneOpening {
    public static let url = URL(string: "x-apple.systempreferences:com.apple.Wallpaper-Settings.extension")

    public init() {}

    public func openWallpaperPane() -> Bool {
        guard let url = Self.url else { return false }
        return NSWorkspace.shared.open(url)
    }
}
