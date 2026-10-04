import AppKit
import Foundation
import LivepaperCore
import LivepaperPlayback
import os
import WallpaperAgentBridge

extension Logger {
    /// `PlaybackSupervisor`'s lines (`SupervisorLog`).
    nonisolated static let supervisor = Logger(subsystem: WallpaperExtensionIdentity.logSubsystem, category: "supervisor")
    /// The lines of each surface's layer tree and engines, the metrics line among them.
    nonisolated static let surface = Logger(subsystem: WallpaperExtensionIdentity.logSubsystem, category: "surface")
}

/// The extension's own lines, under its subsystem, category `extension`. The
/// spec's on-screen checks read them, so each wording is fixed here and
/// nowhere else, as a phrase and then `key=value` fields, as the supervisor's are.
/// The heartbeat is not logged: it beats every few seconds for as long as the
/// extension runs.
nonisolated enum ExtensionLog {
    static let logger = Logger(subsystem: WallpaperExtensionIdentity.logSubsystem, category: "extension")

    static func notice(_ line: Line) {
        logger.notice("\(line.text, privacy: .public)")
    }

    static func error(_ line: Line) {
        logger.error("\(line.text, privacy: .public)")
    }

    struct Line {
        let text: String
    }
}

nonisolated extension ExtensionLog.Line {
    // MARK: Launch

    static func launched(pid: Int32, version: String, build: String, bundle: String) -> Self {
        Self(text: "extension: launched pid=\(pid) version=\(version) build=\(build) bundle=\(bundle)")
    }

    static func noHome(fallback: URL) -> Self {
        Self(text: "extension: no home folder from getpwuid, reading the library under \(fallback.path(percentEncoded: false))")
    }

    static let noSettingsTile = Self(text: "extension: the settings tile is missing from the bundle")

    static func cannotObserve(_ what: String) -> Self {
        Self(text: "extension: cannot observe \(what)")
    }

    /// The first time a scene asks where the pointer is: where it was, and the display's frame, in AppKit's coordinates.
    static func pointerRead(_ location: NSPoint, display: CGRect) -> Self {
        let place = "x=\(Int(location.x)) y=\(Int(location.y))"
        let frame = "\(Int(display.minX)),\(Int(display.minY)) \(Int(display.width))x\(Int(display.height))"
        return Self(text: "extension: pointer read \(place) on display \(frame)")
    }

    // MARK: Surfaces

    static func contextMade(_ surface: SurfaceID, context: RemoteContextID?, display: DisplayIdentity, isPreview: Bool) -> Self {
        Self(text: "extension: context made surface=\(surface) context=\(name(context)) display=\(display) preview=\(isPreview)")
    }

    static func noContext(_ surface: SurfaceID) -> Self {
        Self(text: "extension: no context surface=\(surface), the agent is answered with none")
    }

    static func noDisplay(_ surface: SurfaceID) -> Self {
        Self(text: "extension: no display surface=\(surface), the agent is answered with none")
    }

    static func unknownDisplay(_ displayID: UInt32, surface: SurfaceID) -> Self {
        Self(text: "extension: display unknown displayID=\(displayID) surface=\(surface), taken for the main display")
    }

    static func acquireLate(_ surface: SurfaceID, context: RemoteContextID?) -> Self {
        Self(text: "extension: acquire not done after 2 s surface=\(surface), answered context=\(name(context))")
    }

    static func contextInvalidated(_ surface: SurfaceID, context: RemoteContextID?) -> Self {
        Self(text: "extension: context invalidated surface=\(surface) context=\(name(context))")
    }

    static func surfaceResized(_ surface: SurfaceID, from old: SurfaceGeometry, to new: SurfaceGeometry) -> Self {
        Self(text: "extension: surface resized surface=\(surface) from=\(text(old)) to=\(text(new))")
    }

    static func snapshotElsewhere(asked: UUID?, taken: SurfaceID) -> Self {
        Self(text: "extension: snapshot of unknown surface=\(asked?.uuidString ?? "none") taken from surface=\(taken)")
    }

    static func snapshotLate(_ surface: SurfaceID) -> Self {
        Self(text: "extension: snapshot not done after 2 s surface=\(surface), answered the neutral colour")
    }

    // MARK: The system

    enum WakeSource: String {
        case system
        case displays
    }

    static func woke(_ source: WakeSource) -> Self {
        Self(text: "extension: woke source=\(source.rawValue)")
    }

    static let unlocked = Self(text: "extension: unlocked")

    static func displayReconfigured(_ display: DisplayIdentity, from old: SurfaceGeometry?, to new: SurfaceGeometry) -> Self {
        Self(text: "extension: display reconfigured display=\(display) from=\(old.map(text) ?? "none") to=\(text(new))")
    }

    static func cannotWatchReconfiguration(_ error: Int32) -> Self {
        Self(text: "extension: cannot watch display reconfiguration, CGError \(error)")
    }

    // MARK: The app

    static func recoverReceived(_ level: RecoveryLevel) -> Self {
        Self(text: "extension: recover received level=\(level)")
    }

    static func recoverIgnored(state: UInt64) -> Self {
        Self(text: "extension: recover ignored state=\(state)")
    }

    static let checkReceived = Self(text: "extension: check received")

    static func metricsProbe(_ on: Bool) -> Self {
        Self(text: "extension: playback metrics probe \(on ? "on" : "off")")
    }

    private static func name(_ context: RemoteContextID?) -> String {
        context?.description ?? "none"
    }

    /// Points and scale, as the bridge's lines give a destination: `1800x1169@2.0`.
    private static func text(_ geometry: SurfaceGeometry) -> String {
        "\(Int(geometry.size.width))x\(Int(geometry.size.height))@\(geometry.scale)"
    }
}
