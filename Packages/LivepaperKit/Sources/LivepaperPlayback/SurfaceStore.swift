// Surfaces that outlive the agent's connection, and the grace before one is
// torn down, follow Phosphene's WallpaperXPCHandler.swift and
// WallpaperState.swift (MIT, (c) 2026 kageroumado,
// https://github.com/kageroumado/phosphene), by way of the spike's
// SurfaceStore. See NOTICE at the repository root.

import Foundation
import LivepaperCore

/// Where the agent is showing a surface, as its `update` says. Not a
/// `Presentation`, which is how a wallpaper is fitted to a display.
public enum SurfaceMode: String, Equatable, Sendable {
    case desktop
    /// The lock screen: the same surface, above every window.
    case locked
}

/// What the extension is to do with a surface's remote `CAContext`. The store
/// decides; the extension holds the contexts.
public enum SurfaceStoreEffect: Equatable, Sendable {
    /// A surface the store did not know: make its context and layer tree.
    case create(SurfaceID)
    /// A surface it knows, live or within its grace: reply with its context as it is.
    case reuse(SurfaceID)
    /// Invalidated and not re-acquired in time: invalidate its context and let its layer tree go.
    case tearDown(SurfaceID)
}

/// The surfaces the agent has acquired, by surface ID: which display
/// each belongs to, whether it is the Settings preview, and whether the agent
/// still shows it.
///
/// The agent drops and re-makes connections routinely, so an invalidated
/// surface is kept for `teardownGrace` in case it is acquired again. A replug
/// is a new surface ID for the same display, and the old one never returns, so
/// what a surface shows comes from its display, never from the surface.
public struct SurfaceStore: Equatable, Sendable {
    public static let teardownGrace: Duration = .seconds(15)

    public struct Entry: Equatable, Sendable {
        public var display: DisplayIdentity
        public var isPreview: Bool
        public var mode: SurfaceMode
        /// When the agent let go of it; `nil` while it is live.
        public var invalidatedAt: Date?

        public init(display: DisplayIdentity, isPreview: Bool, mode: SurfaceMode = .desktop, invalidatedAt: Date? = nil) {
            self.display = display
            self.isPreview = isPreview
            self.mode = mode
            self.invalidatedAt = invalidatedAt
        }

        public var isLive: Bool { invalidatedAt == nil }
    }

    public private(set) var entries: [SurfaceID: Entry] = [:]

    public init() {}

    /// The agent acquired a surface. One it knows, live or invalidated, is reused.
    public mutating func acquire(_ surface: SurfaceID, display: DisplayIdentity, isPreview: Bool) -> SurfaceStoreEffect {
        if var entry = entries[surface] {
            entry.display = display
            entry.isPreview = isPreview
            entry.invalidatedAt = nil
            entries[surface] = entry
            return .reuse(surface)
        }
        entries[surface] = Entry(display: display, isPreview: isPreview)
        return .create(surface)
    }

    /// The agent let go of a surface: it is torn down `teardownGrace` from now
    /// unless it is acquired again. `false` for a surface the store does not know.
    @discardableResult
    public mutating func invalidate(_ surface: SurfaceID, at now: Date) -> Bool {
        guard entries[surface] != nil else { return false }
        if entries[surface]?.invalidatedAt == nil { entries[surface]?.invalidatedAt = now }
        return true
    }

    /// `false` for a surface the store does not know.
    public mutating func update(_ surface: SurfaceID, mode: SurfaceMode) -> Bool {
        guard entries[surface] != nil else { return false }
        entries[surface]?.mode = mode
        return true
    }

    /// Forgets the surfaces whose grace has run out by `now`.
    public mutating func tearDown(at now: Date) -> [SurfaceStoreEffect] {
        let expired = entries
            .filter { _, entry in entry.invalidatedAt.map { Self.graceEnd(after: $0) <= now } ?? false }
            .keys.sorted { $0.description < $1.description }
        for surface in expired { entries[surface] = nil }
        return expired.map(SurfaceStoreEffect.tearDown)
    }

    /// When `tearDown(at:)` next has something to do.
    public var nextTeardown: Date? {
        entries.values.compactMap { $0.invalidatedAt.map(Self.graceEnd) }.min()
    }

    /// The heartbeat's `desktopSurfaceAcquired`: Livepaper is the selected wallpaper.
    public var hasLiveDesktopSurface: Bool {
        entries.values.contains { $0.isLive && !$0.isPreview }
    }

    public var liveSurfaces: [SurfaceID] {
        entries.filter { $0.value.isLive }.keys.sorted { $0.description < $1.description }
    }

    public func liveSurfaces(on display: DisplayIdentity) -> [SurfaceID] {
        liveSurfaces.filter { entries[$0]?.display == display }
    }

    /// What a surface is to show: its display's assignment, whatever surface
    /// ID it came back as, or nothing for a surface the store does not know.
    public func target(
        for surface: SurfaceID, in current: CurrentRenderState, location: LibraryLocation, host: HostCapabilities, now: Date
    ) -> SurfaceTarget {
        guard let entry = entries[surface] else { return .nothing }
        return current.target(for: entry.display, location: location, host: host, now: now)
    }

    private static func graceEnd(after invalidatedAt: Date) -> Date {
        invalidatedAt.addingTimeInterval(teardownGrace / .seconds(1))
    }
}
