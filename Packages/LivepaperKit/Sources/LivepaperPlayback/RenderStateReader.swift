import Foundation
import LivepaperCore

/// What one read of `render-state.json` found.
public enum RenderStateRead: Equatable, Sendable {
    /// There is no file: the app has never written one, or the library is gone.
    case missing
    /// The file is there but cannot be trusted: unopenable, malformed, naming a
    /// path outside the library, or of a major version this build does not
    /// know. The reason is for the log.
    case unreadable(String)
    case read(RenderState)
}

/// Reads the render state the app wrote, with no app needed:
/// the extension reads the last one at launch and again on each notification.
public struct RenderStateReader: Sendable {
    public let location: LibraryLocation

    /// `location` is built from the real home folder, which inside the sandbox
    /// only `getpwuid` gives.
    public init(location: LibraryLocation) {
        self.location = location
    }

    /// Reads the file. It is a few kilobytes, so the read is synchronous and
    /// runs on the caller's actor: in the extension, the main actor, when the
    /// notification arrives.
    public func read() -> RenderStateRead {
        let data: Data
        do {
            data = try Data(contentsOf: location.renderState)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .missing
        } catch {
            return .unreadable(Self.reason(for: error))
        }
        do {
            return .read(try RenderState.decode(data))
        } catch {
            return .unreadable(Self.reason(for: error))
        }
    }

    private static func reason(for error: any Error) -> String {
        switch error {
        case SchemaError.unsupportedVersion(let version): "unknown schema version \(version)"
        case is LibraryPathError: "a path outside the library"
        case is DecodingError: "malformed"
        default: "cannot be opened (\((error as NSError).domain) \((error as NSError).code))"
        }
    }
}

/// The render state the extension goes by: the last one it could read, or none.
public enum CurrentRenderState: Equatable, Sendable {
    /// Nothing readable has arrived, or the file is gone: the neutral colour.
    case none
    case state(RenderState)

    /// What is shown after a read: a missing file shows nothing, a file that
    /// cannot be trusted keeps what is shown, and anything readable applies,
    /// the stopped state included.
    public func applying(_ read: RenderStateRead) -> CurrentRenderState {
        switch read {
        case .missing: .none
        case .unreadable: self
        case .read(let state): .state(state)
        }
    }

    public var renderState: RenderState? {
        guard case .state(let state) = self else { return nil }
        return state
    }

    /// The generation the heartbeat acknowledges, or `nil` with no state.
    public var generation: UInt64? { renderState?.generation }

    /// The heartbeat's `holdingStill`: the stopped state, or none it could read.
    public var isHoldingStill: Bool { renderState?.isStopped ?? true }

    /// What the surfaces of `display` are to show. `now` is the wall clock,
    /// since the app stamps its sensed conditions with it.
    public func target(for display: DisplayIdentity, location: LibraryLocation, host: HostCapabilities, now: Date) -> SurfaceTarget {
        guard let state = renderState, let assignment = state.displays.first(where: { $0.identity == display }) else { return .nothing }
        let wallpaper = SurfaceWallpaper(assignment, in: location)
        if state.isStopped { return .still(wallpaper) }
        let decision = decidePlayback(state.playbackConditions(for: display, now: now), rules: state.pauseRules, host: host)
        return .playback(wallpaper, decision)
    }

    /// When the decision for `display` is to be taken again because its
    /// sensed conditions expire, if it is one they made.
    public func expiry(for display: DisplayIdentity, host: HostCapabilities, now: Date) -> Date? {
        guard let state = renderState, !state.isStopped, state.displays.contains(where: { $0.identity == display }) else { return nil }
        let conditions = state.playbackConditions(for: display, now: now)
        return decisionExpiry(of: decidePlayback(conditions, rules: state.pauseRules, host: host), conditions: conditions)
    }
}
