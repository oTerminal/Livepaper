import AVFoundation
import Foundation

/// What `WallpaperAgentBridge.load()` found.
public struct BridgeSelfCheck: Equatable, Sendable {
    let requirements: [BridgeRequirement]

    init(missing: [BridgeRequirement]) {
        requirements = missing
    }

    /// Whether the extension can show wallpapers. When it cannot, the heartbeat
    /// carries `selfCheckFailed` and the app reports the host unavailable.
    public var isUsable: Bool { !requirements.contains(where: \.isEssential) }

    /// The names of what is missing, as the log line gives them.
    public var missing: [String] { requirements.map(\.description) }

    /// The one line the check logs, under the extension's subsystem, category
    /// `bridge`. The soak's log parser reads it; the wording is fixed.
    public var logLine: String {
        guard !requirements.isEmpty else { return "bridge self-check: all present" }
        return "bridge self-check: \(isUsable ? "usable" : "failed"), missing: \(missing.joined(separator: ", "))"
    }
}

/// One thing the extension needs of macOS's private API.
enum BridgeRequirement: Hashable, Sendable, CustomStringConvertible {
    case framework
    case payloadClass(String)
    case remoteContextFactory
    case remoteContextAccessors
    case remoteContextInvalidate
    /// The acquire reply's `box` ivar holds the context ID and nothing else.
    case remoteContextReplyLayout
    /// The snapshot reply's `rawValue` ivar holds the `IOSurface` and nothing else.
    case snapshotReplyLayout
    case videoCompositingSelector

    /// Whether a surface can be acquired without it.
    var isEssential: Bool {
        switch self {
        case .framework, .remoteContextFactory, .remoteContextAccessors, .remoteContextReplyLayout: true
        case let .payloadClass(name): WallpaperAgentBridge.essentialClassNames.contains(name)
        case .remoteContextInvalidate, .snapshotReplyLayout, .videoCompositingSelector: false
        }
    }

    var description: String {
        switch self {
        case .framework: "WallpaperExtensionKit"
        case let .payloadClass(name): name
        case .remoteContextFactory: "+[CAContext remoteContextWithOptions:]"
        case .remoteContextAccessors: "-[CAContext contextId layer setLayer:]"
        case .remoteContextInvalidate: "-[CAContext invalidate]"
        case .remoteContextReplyLayout: "\(ReplySlot.remoteContext.className).\(ReplySlot.remoteContext.ivar)"
        case .snapshotReplyLayout: "\(ReplySlot.snapshot.className).\(ReplySlot.snapshot.ivar)"
        case .videoCompositingSelector: "-[AVSampleBufferDisplayLayer _setDisallowsVideoLayerDisplayCompositing:]"
        }
    }

    /// Looks for each requirement in this process, loading the framework first.
    /// Without the framework its classes and layouts are not listed one by one,
    /// nor a layout whose class is missing.
    static func probeMissing() -> [BridgeRequirement] {
        var missing: [BridgeRequirement] = []
        if dlopen(WallpaperAgentBridge.frameworkPath, RTLD_LAZY) == nil {
            missing.append(.framework)
        } else {
            let absent = WallpaperAgentBridge.payloadClassNames.filter { objc_getClass($0) == nil }
            missing += absent.map(BridgeRequirement.payloadClass)
            if !absent.contains(ReplySlot.remoteContext.className), ReplySlot.remoteContext.offset == nil {
                missing.append(.remoteContextReplyLayout)
            }
            if !absent.contains(ReplySlot.snapshot.className), ReplySlot.snapshot.offset == nil {
                missing.append(.snapshotReplyLayout)
            }
        }
        if !RemoteContextAPI.hasFactory {
            missing.append(.remoteContextFactory)
        }
        if !RemoteContextAPI.hasAccessors {
            missing.append(.remoteContextAccessors)
        }
        if !RemoteContextAPI.canInvalidate {
            missing.append(.remoteContextInvalidate)
        }
        if !AVSampleBufferDisplayLayer.instancesRespond(to: WallpaperAgentBridge.videoCompositingSelector) {
            missing.append(.videoCompositingSelector)
        }
        return missing
    }
}

/// Where a reply's value is written into an object of a private class: the
/// named ivar, which must be the object's only storage and one word at most.
/// On macOS 27.0 both classes are 16 bytes with their ivar at 8. A class that
/// grew fails closed rather than being written past.
struct ReplySlot: Sendable {
    let className: String
    let ivar: String
    /// The bytes written.
    let width: Int

    static let remoteContext = ReplySlot(className: "WallpaperRemoteContextXPC", ivar: "box", width: MemoryLayout<UInt32>.size)
    static let snapshot = ReplySlot(className: "WallpaperSnapshotXPC", ivar: "rawValue", width: MemoryLayout<UnsafeRawPointer>.size)

    var type: AnyClass? { objc_getClass(className) as? AnyClass }

    /// The ivar's offset, or `nil` when the layout is not the expected one.
    var offset: Int? {
        guard let type, let variable = class_getInstanceVariable(type, ivar) else { return nil }
        let offset = ivar_getOffset(variable)
        let room = class_getInstanceSize(type) - offset
        guard offset >= MemoryLayout<UnsafeRawPointer>.size, room >= width, room <= MemoryLayout<UInt64>.size else { return nil }
        return offset
    }
}
