import Foundation
import LivepaperCore
import os

extension Logger {
    /// The bridge's lines, under the extension's subsystem.
    static let bridge = Logger(subsystem: WallpaperExtensionIdentity.logSubsystem, category: "bridge")
}

/// The wording of every line the bridge logs besides the self-check's
/// (`BridgeSelfCheck.logLine`). The on-screen checks read them, so
/// they are fixed here, in one place.
enum BridgeLog {
    static func accepted(pid: Int32) -> String {
        "bridge: connection from pid \(pid) accepted"
    }

    static func ended(pid: Int32, served: Bool, emptyInARow: Int) -> String {
        served
            ? "bridge: connection from pid \(pid) ended, served"
            : "bridge: connection from pid \(pid) ended without a call, \(emptyInARow) in a row"
    }

    static func spiral(emptyInARow: Int) -> String {
        "bridge: spiral detected, \(emptyInARow) empty connections in a row; the app is asked to restart WallpaperAgent"
    }

    static func acquire(_ request: AcquireRequest, identified: Bool) -> String {
        let surface = identified ? request.surface.uuidString : "\(request.surface.uuidString) (unidentified by the agent)"
        return "bridge: acquire surface \(surface) \(fields(request.destination)) preview \(request.isPreview) "
            + "presentationMode=\(name(request.mode)) activityState=\(name(request.activityState))"
    }

    static func update(_ request: UpdateRequest) -> String {
        "bridge: update surface \(request.surface?.uuidString ?? "none") \(fields(request.destination)) "
            + "presentationMode=\(name(request.mode)) activityState=\(name(request.activityState))"
    }

    static func invalidate(surface: UUID?) -> String {
        "bridge: invalidate surface \(surface?.uuidString ?? "none")"
    }

    static func snapshot(surface: UUID?, picture: Bool) -> String {
        "bridge: snapshot surface \(surface?.uuidString ?? "none") -> \(picture ? "picture" : "neutral colour")"
    }

    static func acquireFailed(surface: UUID) -> String {
        "bridge: acquire surface \(surface.uuidString) failed"
    }

    static func replyUnbuilt(_ className: String) -> String {
        "bridge: could not build a \(className) reply"
    }

    static func secondReply(_ call: String) -> String {
        "bridge: a second reply to \(call) was dropped"
    }

    private static func fields(_ destination: SurfaceDestination) -> String {
        let display = destination.display.map(String.init) ?? "none"
        let size = destination.size.map { "\(Int($0.width))x\(Int($0.height))" } ?? "none"
        let scale = destination.scale.map { "\($0)" } ?? "none"
        return "display \(display) size \(size)@\(scale)"
    }

    private static func name(_ value: (some CustomStringConvertible)?) -> String {
        value?.description ?? "none"
    }
}
