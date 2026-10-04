// The acquire flow (a context per surface, the layer tree in it and flushed before the reply, the
// reply once there is something to show) follows Phosphene's WallpaperXPCHandler.swift (MIT,
// (c) 2026 kageroumado, https://github.com/kageroumado/phosphene). See NOTICE at the repository root.

import Foundation
import IOSurface
import LivepaperCore
import LivepaperPlayback
import WallpaperAgentBridge

/// WallpaperAgent's calls on the extension's surfaces, turned into calls on
/// the supervisor. The bridge makes them on the connection's XPC queue; each
/// hops to the main actor, where the surfaces and the supervisor live, with
/// `DispatchQueue.main.async`, which keeps the agent's order, and returns.
///
/// Marked `@MainActor` because the target's default does not reach a type
/// that conforms to a `Sendable` protocol; that is also what makes it `Sendable`.
@MainActor
final class AgentRequests: SurfaceRequestHandler {
    /// The longest the agent waits for an acquire's or a snapshot's answer.
    static let replyLimit: Duration = .seconds(2)

    private let hosted: HostedSurfaces
    private let supervisor: PlaybackSupervisor
    /// Weak because the listener holds these requests and the beacon holds the listener.
    weak var beacon: HeartbeatBeacon?

    init(hosted: HostedSurfaces, supervisor: PlaybackSupervisor) {
        self.hosted = hosted
        self.supervisor = supervisor
    }

    // MARK: SurfaceRequestHandler, on the XPC queue

    nonisolated func acquire(_ request: AcquireRequest, reply: @escaping @Sendable (RemoteContextID?) -> Void) {
        DispatchQueue.main.async { self.acquireSurface(request, reply: reply) }
    }

    nonisolated func update(_ request: UpdateRequest) {
        DispatchQueue.main.async { self.updateSurface(request) }
    }

    nonisolated func invalidate(surface: UUID) {
        DispatchQueue.main.async { self.invalidateSurface(SurfaceID(uuid: surface)) }
    }

    nonisolated func snapshot(surface: UUID?, reply: @escaping @Sendable (IOSurface?) -> Void) {
        DispatchQueue.main.async { self.snapshotSurface(surface, reply: reply) }
    }

    nonisolated func spiralDetected() {
        DispatchQueue.main.async { self.beacon?.post() }
    }

    // MARK: On the main actor

    /// A surface the extension does not host gets its context before the
    /// supervisor hears of it, so that one the render server refuses is never
    /// played. The agent is answered with the context once the supervisor has
    /// told the surface what to show, or after `replyLimit`, whichever is first.
    private func acquireSurface(_ request: AcquireRequest, reply: @escaping @Sendable (RemoteContextID?) -> Void) {
        let surface = SurfaceID(uuid: request.surface)
        guard let placement = SurfacePlacement(request.destination, surface: surface) else {
            ExtensionLog.error(.noDisplay(surface))
            reply(nil)
            return
        }
        let context: RemoteContext
        if let known = hosted[surface] {
            context = known.context
            known.reacquired(at: placement)
        } else if let made = RemoteContext(display: request.destination.display) {
            context = made
            ExtensionLog.notice(.contextMade(surface, context: made.id, display: placement.display, isPreview: request.isPreview))
        } else {
            ExtensionLog.error(.noContext(surface))
            reply(nil)
            return
        }

        let hosted = hosted
        let supervisor = supervisor
        let answer = AgentReply(within: Self.replyLimit, reply: reply) {
            let id = hosted[surface]?.context.id
            ExtensionLog.error(.acquireLate(surface, context: id))
            return id
        }
        // Immediate, so that the supervisor's store is asked in this same turn
        // of the main actor as `hosted` was: no teardown can come between them.
        Task.immediate {
            _ = await supervisor.acquire(
                surface,
                display: placement.display,
                isPreview: request.isPreview,
                geometry: placement.geometry,
                makeSurface: { hosted.host(surface, in: context, at: placement) }
            )
            answer.send(hosted[surface]?.context.id)
            self.follow(request.mode, of: surface)
            self.beacon?.postIfChanged()
        }
    }

    /// Where the surface is shown now, and perhaps its new size. The agent
    /// sends it on locking, unlocking and the screen saver, and the supervisor
    /// takes it as a moment to check.
    private func updateSurface(_ request: UpdateRequest) {
        guard let uuid = request.surface else {
            // The agent's identifier could not be read. Something changed all
            // the same, and the supervisor takes it as it takes any update.
            supervisor.agentUpdated()
            return
        }
        let surface = SurfaceID(uuid: uuid)
        if let hosted = hosted[surface], let size = request.destination.size, size.width > 0, size.height > 0 {
            let scale = request.destination.scale.flatMap { $0 > 0 ? $0 : nil } ?? hosted.geometry.scale
            let geometry = SurfaceGeometry(size: size, scale: scale)
            if geometry != hosted.geometry {
                ExtensionLog.notice(.surfaceResized(surface, from: hosted.geometry, to: geometry))
                hosted.geometry = geometry
                supervisor.layout(surface, geometry: geometry)
            }
        }
        let mode = SurfaceMode(request.mode) ?? supervisor.entry(for: surface)?.mode ?? .desktop
        supervisor.update(surface, mode: mode)
    }

    /// An acquire that says the surface is not on the desktop, as when a
    /// display comes back while the Mac is locked, is followed as an update would be.
    private func follow(_ agentMode: AgentSurfaceMode?, of surface: SurfaceID) {
        guard let mode = SurfaceMode(agentMode), let entry = supervisor.entry(for: surface), mode != entry.mode else { return }
        supervisor.update(surface, mode: mode)
    }

    private func invalidateSurface(_ surface: SurfaceID) {
        supervisor.invalidate(surface)
        beacon?.postIfChanged()
    }

    /// The picture on screen, cropped as the layers show it, or `nil` for the
    /// neutral colour: with no surface to take it from, or after `replyLimit`.
    private func snapshotSurface(_ surface: UUID?, reply: @escaping @Sendable (IOSurface?) -> Void) {
        guard let source = hosted.snapshotSource(for: surface.map(SurfaceID.init), asking: supervisor) else {
            reply(nil)
            return
        }
        if source.id.uuid != surface {
            ExtensionLog.notice(.snapshotElsewhere(asked: surface, taken: source.id))
        }
        let layers = source.layers
        let answer = AgentReply(within: Self.replyLimit, reply: reply) {
            ExtensionLog.error(.snapshotLate(source.id))
            return nil
        }
        Task {
            answer.send(await layers.snapshotPicture())
        }
    }
}

extension SurfaceMode {
    /// The supervisor's mode for the agent's, or `nil` when the agent's says
    /// nothing it can use: the surface then keeps the mode it has.
    ///
    /// The screen saver (`.idle`) counts as the lock screen: like it, it is
    /// shown above every window, so a covered display is still on screen for
    /// the watchdog.
    init?(_ mode: AgentSurfaceMode?) {
        switch mode {
        case .desktop: self = .desktop
        case .locked, .idle: self = .locked
        case .other, nil: return nil
        }
    }
}
