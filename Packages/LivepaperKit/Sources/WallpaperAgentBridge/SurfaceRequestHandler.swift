import Foundation
import IOSurface

/// What the extension does when WallpaperAgent asks something of a surface,
/// with the agent's private payloads already read into typed values.
///
/// Every call arrives on the connection's XPC queue, never on the main actor,
/// and must return at once. An implementation hops to the main actor with
/// `DispatchQueue.main.async`, which keeps the agent's calls in the order they
/// came, does the work there, and answers through `reply` when it has the
/// answer. A reply may be called from any thread and is meant to be called
/// once; a second call is dropped and logged.
///
///     nonisolated func acquire(_ request: AcquireRequest, reply: @escaping @Sendable (RemoteContextID?) -> Void) {
///         DispatchQueue.main.async { self.store.acquire(request, reply: reply) }
///     }
public protocol SurfaceRequestHandler: AnyObject, Sendable {
    /// The agent wants a surface. Build its layer tree, host it in a
    /// `RemoteContext`, and reply with the context's ID, or `nil` when there
    /// is none. The agent starts hosting when the reply arrives, so reply once
    /// there is something to show, and within 2 s in any case.
    /// A surface the agent acquires
    /// again gets the context it has.
    func acquire(_ request: AcquireRequest, reply: @escaping @Sendable (RemoteContextID?) -> Void)

    /// What a surface is showing for has changed. The agent has been answered.
    func update(_ request: UpdateRequest)

    /// The agent has given a surface up. The agent has been answered; the
    /// surface is kept for a while in case it comes back.
    func invalidate(surface: UUID)

    /// The agent wants a still of a surface to show while it hosts no live
    /// context, as on the way to the lock screen. Reply with the picture on
    /// screen, cropped as the layer shows it, or `nil` for the neutral colour.
    /// `surface` is `nil` when the agent's identifier could not be read.
    func snapshot(surface: UUID?, reply: @escaping @Sendable (IOSurface?) -> Void)

    /// WallpaperAgent is reconnecting in a loop: post a heartbeat now, so that
    /// the app sees `spiralDetected` at once rather than at the next beat. The
    /// flag itself is `WallpaperAgentListener.isSpiralling(at:)`.
    func spiralDetected()
}
