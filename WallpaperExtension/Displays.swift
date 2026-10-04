import ColorSync
import CoreGraphics
import Foundation
import LivepaperCore
import LivepaperPlayback
import WallpaperAgentBridge

/// What CoreGraphics says about a display. The agent names a display by its
/// `CGDirectDisplayID`, which can change across a replug; assignments are
/// keyed by its UUID, read here the way the app's display sensor reads it.
nonisolated enum Displays {
    static func identity(of display: CGDirectDisplayID) -> DisplayIdentity? {
        guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(display)?.takeRetainedValue(),
              let uuid = UUID(uuidString: CFUUIDCreateString(nil, cfUUID) as String)
        else { return nil }
        return DisplayIdentity(uuid: uuid)
    }

    /// The display's size in points and its backing scale, the current mode's
    /// pixel width over its width. `nil` for a display CoreGraphics does not know.
    static func geometry(of display: CGDirectDisplayID) -> SurfaceGeometry? {
        let bounds = CGDisplayBounds(display)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let scale = CGDisplayCopyDisplayMode(display).flatMap { mode in
            mode.width > 0 ? Double(mode.pixelWidth) / Double(mode.width) : nil
        }
        return SurfaceGeometry(size: Size(width: bounds.width, height: bounds.height), scale: scale ?? 1)
    }

    /// The online display with this identity, now.
    static func display(with identity: DisplayIdentity) -> CGDirectDisplayID? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &displays, &count) == .success else { return nil }
        return displays.prefix(Int(count)).first { self.identity(of: $0) == identity }
    }
}

/// Where the agent wants a surface: the display it belongs to, and the size to
/// lay it out at.
struct SurfacePlacement: Equatable {
    var display: DisplayIdentity
    var geometry: SurfaceGeometry
    /// The display's own geometry as CoreGraphics gives it, which a later
    /// reconfiguration is compared with. `nil` when CoreGraphics has none.
    var displayGeometry: SurfaceGeometry?

    /// `nil` when not even the main display has an identity, or nothing gives a size.
    ///
    /// The Settings preview comes with display ID 0, or none, and belongs to
    /// the main display. A display CoreGraphics no longer knows, gone between
    /// the agent's request and this, is taken for the main display too: the
    /// surface shows something rather than nothing, and its display's surfaces
    /// come back under a new ID when it returns.
    ///
    /// The size and scale are the agent's, which are the surface's, where it
    /// gives them; otherwise the display's.
    init?(_ destination: SurfaceDestination, surface: SurfaceID) {
        let named = destination.display.flatMap { $0 == 0 ? nil : $0 }
        var displayID = named ?? CGMainDisplayID()
        var identity = Displays.identity(of: displayID)
        if identity == nil, let named {
            ExtensionLog.error(.unknownDisplay(named, surface: surface))
            displayID = CGMainDisplayID()
            identity = Displays.identity(of: displayID)
        }
        guard let identity else { return nil }

        let displayGeometry = Displays.geometry(of: displayID)
        let size = destination.size.flatMap { $0.width > 0 && $0.height > 0 ? $0 : nil }
        let scale = destination.scale.flatMap { $0 > 0 ? $0 : nil }
        guard let size = size ?? displayGeometry?.size else { return nil }
        self.display = identity
        self.geometry = SurfaceGeometry(size: size, scale: scale ?? displayGeometry?.scale ?? 1)
        self.displayGeometry = displayGeometry
    }
}
