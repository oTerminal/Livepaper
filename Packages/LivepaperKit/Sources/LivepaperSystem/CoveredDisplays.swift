import CoreGraphics
import LivepaperCore

/// One on-screen window as the window list gives it without Screen Recording:
/// where it is, its level and its owner, never its name.
nonisolated public struct WindowListEntry: Equatable, Sendable {
    /// Global display space, in points, y growing downwards.
    public var bounds: Rect
    public var layer: Int
    public var ownerPID: Int32

    public init(bounds: Rect, layer: Int, ownerPID: Int32) {
        self.bounds = bounds
        self.layer = layer
        self.ownerPID = ownerPID
    }

    /// The levels at which a window covers the desktop: the normal level and
    /// everything above it, the screen saver and the shielding window included.
    /// The desktop's own windows sit below.
    public static let coveringLevels = Int(CGWindowLevelForKey(.normalWindow))...
}

/// What one read of the window list says.
nonisolated public struct WindowListReading: Equatable, Sendable {
    /// The displays whose desktop is fully covered (`coveredDisplays`).
    public var covered: Set<DisplayIdentity>
    /// Whether Show Desktop has the windows aside (`isShowingDesktop`).
    public var showingDesktop: Bool

    public init(covered: Set<DisplayIdentity> = [], showingDesktop: Bool = false) {
        self.covered = covered
        self.showingDesktop = showingDesktop
    }
}

/// The displays whose desktop is fully covered: one window on screen at a
/// covering level, not owned by one of `ignoredOwners`, contains the display's
/// frame, less the strip beside a camera housing.
///
/// A fullscreen app on a display with a camera housing starts below the menu
/// bar, and the strip beside the housing is black: the desktop is not
/// composited there either. The owners to ignore are the app itself, the
/// Dock, which keeps a display-sized window on every display, above the
/// normal level, that covers nothing, loginwindow, whose lock screen
/// shield is display-sized too and stays listed for about a second after the
/// unlock: the lock screen is the lock sensor's business, and WindowManager,
/// whose Show Desktop window is display-sized above the normal level while
/// the desktop shows through it (`isShowingDesktop`). Several windows
/// that cover a display between them do not count; that is v1's known gap. A
/// zoomed window leaves the menu bar, where the wallpaper shows through, so
/// it does not count either, except in one case: with the Dock hidden, a
/// zoomed window below a camera housing has a fullscreen window's bounds, so
/// it counts although the menu bar still shows a strip of wallpaper, and the
/// wallpaper pauses under it.
nonisolated public func coveredDisplays(
    windows: [WindowListEntry],
    displays: [ConnectedDisplay],
    ignoringOwners ignoredOwners: Set<Int32>
) -> Set<DisplayIdentity> {
    let covering = windows.filter { !ignoredOwners.contains($0.ownerPID) && WindowListEntry.coveringLevels.contains($0.layer) }
    return Set(
        displays
            .filter { display in covering.contains { $0.bounds.contains(display.frameToCover) } }
            .map(\.identity)
    )
}

/// Whether Show Desktop has the windows aside: one of `windowManager`'s
/// windows, at a covering level, contains a display's frame.
///
/// On macOS 27 Show Desktop slides every window almost off the display,
/// leaving a 12 pt sliver at its edge, and WindowManager lists a window of its
/// own over the whole display at level 18, which the desktop shows through and
/// which takes the click that brings the windows back. The windows keep their
/// place in the on-screen list, at their new bounds, and nothing is posted
/// when they leave or when they come back.
nonisolated public func isShowingDesktop(
    windows: [WindowListEntry],
    displays: [ConnectedDisplay],
    windowManager: Set<Int32>
) -> Bool {
    let windowManagers = windows.filter { windowManager.contains($0.ownerPID) }
    return !coveredDisplays(windows: windowManagers, displays: displays, ignoringOwners: []).isEmpty
}

extension ConnectedDisplay {
    /// The menu bar ends this far below the camera housing's strip, and a
    /// fullscreen window starts where the menu bar ends: 39 pt down on a
    /// display whose safe-area inset is 38 pt.
    nonisolated static let menuBarHairline = 1.0

    /// What a window has to contain to cover the display: all of it, less the
    /// strip beside the camera housing and the menu bar's hairline below it.
    /// The menu bar ends on a whole point, so an inset that is not whole rounds up.
    nonisolated var frameToCover: Rect {
        guard topSafeAreaInset > 0 else { return frame }
        let strip = min(topSafeAreaInset.rounded(.up) + Self.menuBarHairline, frame.size.height)
        return Rect(
            origin: Point(x: frame.origin.x, y: frame.origin.y + strip),
            size: Size(width: frame.size.width, height: frame.size.height - strip)
        )
    }
}

extension Rect {
    nonisolated func contains(_ other: Rect) -> Bool {
        origin.x <= other.origin.x && origin.y <= other.origin.y && maxX >= other.maxX && maxY >= other.maxY
    }
}
