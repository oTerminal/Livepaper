// The framework, the payload classes and the video layer selector are the ones
// Phosphene uses (MIT, (c) 2026 kageroumado, https://github.com/kageroumado/phosphene);
// see NOTICE at the repository root.

import AVFoundation
import Foundation
import os

/// Every private API the wallpaper extension uses, and nothing else. Only the
/// extension links this module.
///
/// At launch the extension calls `load()`, then hands each connection from
/// WallpaperAgent to a `WallpaperAgentListener`, which turns the agent's calls
/// into calls on the extension's `SurfaceRequestHandler`. Each surface's tree
/// is hosted by a `RemoteContext`, and its video layers go through
/// `disallowDisplayCompositing(_:)`.
public enum WallpaperAgentBridge {
    static let frameworkPath = "/System/Library/PrivateFrameworks/WallpaperExtensionKit.framework/WallpaperExtensionKit"

    /// The classes WallpaperAgent may send or expect back. NSXPC refuses any
    /// class not allowed for the selector and argument it arrives in.
    static let payloadClassNames = [
        "WallpaperIDXPC", "WallpaperCreationRequestXPC", "WallpaperUpdateRequestXPC",
        "WallpaperRemoteContextXPC", "WallpaperSnapshotXPC", "WallpaperContentTypeSetXPC",
        "WallpaperChoiceIDXPC", "WallpaperChoiceIDsXPC", "WallpaperExtensionChoiceRequestXPC",
        "WallpaperChoiceRequestAdditionResultXPC", "WallpaperDebugRequestXPC",
        "WallpaperDebugResponseXPC", "WallpaperMigrationVersionXPC",
        "WallpaperSettingsViewModelsXPC", "AuditTokenXPC",
    ]

    /// The payload classes without which no surface can be acquired: the
    /// others only serve calls that can fail without the wallpaper going.
    static let essentialClassNames: Set = ["WallpaperIDXPC", "WallpaperCreationRequestXPC", "WallpaperRemoteContextXPC"]

    /// Loads WallpaperExtensionKit and checks that everything the extension
    /// needs of it, of `CAContext` and of the video layer is there, and logs one
    /// line saying what is missing. Call it once, at launch, before accepting a
    /// connection; the heartbeat carries `selfCheckFailed` when the result is
    /// not usable.
    @discardableResult
    public static func load() -> BridgeSelfCheck {
        let check = BridgeSelfCheck(missing: BridgeRequirement.probeMissing())
        if check.isUsable && check.missing.isEmpty {
            Logger.bridge.notice("\(check.logLine, privacy: .public)")
        } else {
            Logger.bridge.error("\(check.logLine, privacy: .public)")
        }
        return check
    }

    /// Stops an empty video layer painting opaque black before its first
    /// frame, with `-[AVSampleBufferDisplayLayer _setDisallowsVideoLayerDisplayCompositing:]`,
    /// which Apple's own wallpaper extensions use. A no-op when it has gone.
    /// Pass it to `SurfaceLayers` as its `prepareVideoLayer`.
    public static func disallowDisplayCompositing(_ layer: AVSampleBufferDisplayLayer) {
        let selector = videoCompositingSelector
        guard layer.responds(to: selector), let implementation = class_getMethodImplementation(type(of: layer), selector) else { return }
        typealias Setter = @convention(c) (AnyObject, Selector, ObjCBool) -> Void
        unsafeBitCast(implementation, to: Setter.self)(layer, selector, true)
    }

    static let videoCompositingSelector = NSSelectorFromString("_setDisallowsVideoLayerDisplayCompositing:")
}
