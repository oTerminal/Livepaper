// One remote context per surface, kept by surface ID so that it outlives the agent's connection, with
// its layer tree set and flushed before the agent is answered, follows Phosphene's
// WallpaperXPCHandler.swift (MIT, (c) 2026 kageroumado, https://github.com/kageroumado/phosphene).
// See NOTICE at the repository root.

import CoreGraphics
import Foundation
import LivepaperCore
import LivepaperPlayback
import LivepaperScene
import QuartzCore
import WallpaperAgentBridge

/// One surface the extension hosts: the remote context WallpaperAgent shows,
/// the layer tree in it, and the sizes the extension compares new ones with.
/// Its display, whether it is the preview, its mode and whether the agent
/// still shows it are the supervisor's to know (`PlaybackSupervisor.entry(for:)`).
final class HostedSurface {
    let id: SurfaceID
    let context: RemoteContext
    /// What the supervisor drives: the layer tree's video, or a scene in its Metal slot.
    let player: SurfacePlayer
    var layers: SurfaceLayers { player.layers }
    /// What the layer tree is laid out for.
    var geometry: SurfaceGeometry
    /// The display's geometry as CoreGraphics last gave it, for the
    /// reconfiguration observer to compare with.
    var displayGeometry: SurfaceGeometry?

    init(id: SurfaceID, context: RemoteContext, player: SurfacePlayer, placement: SurfacePlacement) {
        self.id = id
        self.context = context
        self.player = player
        geometry = placement.geometry
        displayGeometry = placement.displayGeometry
    }

    /// The agent acquired it again, within its grace. The supervisor lays the
    /// tree out for the new geometry itself.
    func reacquired(at placement: SurfacePlacement) {
        geometry = placement.geometry
        displayGeometry = placement.displayGeometry
    }
}

/// The surfaces the extension hosts, by surface ID: their contexts and layer
/// trees, which the supervisor does not hold. A surface is added when the
/// supervisor makes one (`host`) and removed when it tears one down
/// (`tearDown`), in the same turn of the main actor, so a surface here is one
/// the supervisor knows, and what else there is to know of it is asked of the
/// supervisor.
final class HostedSurfaces {
    /// Whether the engines log the metrics line (`HostNotification.playbackMetrics`).
    private(set) var metricsProbe = false
    private var surfaces: [SurfaceID: HostedSurface] = [:]

    subscript(_ surface: SurfaceID) -> HostedSurface? {
        surfaces[surface]
    }

    /// The supervisor's `makeSurface`: the layer tree for a new surface, whole
    /// before it goes into `context`, Metal slot included, and in the render
    /// server before the agent is answered.
    func host(_ surface: SurfaceID, in context: RemoteContext, at placement: SurfacePlacement) -> SurfacePlayer {
        let layers = SurfaceLayers(
            id: surface,
            geometry: placement.geometry,
            logger: .surface,
            prepareVideoLayer: WallpaperAgentBridge.disallowDisplayCompositing
        )
        // What draws a scene, and where the pointer is over its display for the scenes that follow it.
        // A scene it cannot draw holds its poster, still.
        let pointer = DisplayPointer(display: placement.display)
        let player = SurfacePlayer(
            layers: layers, drawingType: WallpaperEngineScene.self, logger: .surface, pointer: { pointer.position() }
        )
        context.layer = layers.root
        CATransaction.flush()
        surfaces[surface] = HostedSurface(id: surface, context: context, player: player, placement: placement)
        if metricsProbe {
            Task { await layers.setMetricsProbe(true) }
        }
        return player
    }

    /// The supervisor's `tearDown`: the agent let the surface go and did not
    /// take it back within the grace. Its context goes now; the supervisor then
    /// empties the layer tree with `showNothing()`, which is the tree's owner's
    /// obligation, and lets it go.
    func tearDown(_ surface: SurfaceID) {
        guard let hosted = surfaces.removeValue(forKey: surface) else { return }
        hosted.context.invalidate()
        ExtensionLog.notice(.contextInvalidated(surface, context: hosted.context.id))
    }

    /// The surface whose picture a snapshot hands back: the one asked for, or,
    /// when the agent's identifier is unknown, a live desktop surface, the
    /// main display's first.
    func snapshotSource(for surface: SurfaceID?, asking supervisor: PlaybackSupervisor) -> HostedSurface? {
        if let surface, let hosted = surfaces[surface] { return hosted }
        let main = Displays.identity(of: CGMainDisplayID())
        let desktops = liveDesktopSurfaces(asking: supervisor).sorted { $0.surface.id.description < $1.surface.id.description }
        return (desktops.first { $0.display == main } ?? desktops.first)?.surface
    }

    /// The live desktop surfaces, by display: the ones the supervisor lays out
    /// again when a display's mode changes.
    func desktopSurfacesByDisplay(asking supervisor: PlaybackSupervisor) -> [DisplayIdentity: [HostedSurface]] {
        Dictionary(grouping: liveDesktopSurfaces(asking: supervisor), by: \.display).mapValues { $0.map(\.surface) }
    }

    /// The surfaces the agent shows on a desktop, and their displays, as the supervisor has them.
    private func liveDesktopSurfaces(asking supervisor: PlaybackSupervisor) -> [(surface: HostedSurface, display: DisplayIdentity)] {
        surfaces.values.compactMap { hosted in
            guard let entry = supervisor.entry(for: hosted.id), entry.isLive, !entry.isPreview else { return nil }
            return (hosted, entry.display)
        }
    }

    /// Switches the probe on every surface, and on those to come. `false` when
    /// it was already so.
    func setMetricsProbe(_ on: Bool) -> Bool {
        guard on != metricsProbe else { return false }
        metricsProbe = on
        for layers in surfaces.values.map(\.layers) {
            Task { await layers.setMetricsProbe(on) }
        }
        return true
    }
}
