// Adapted from Phosphene's WallpaperXPCHandler.swift (MIT, (c) 2026 kageroumado,
// https://github.com/kageroumado/phosphene); see NOTICE at the repository root.

import Foundation
import QuartzCore
import WallpaperAgentBridgeObjC

/// The number WallpaperAgent needs to host a remote context: what an acquire replies.
public struct RemoteContextID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UInt32

    public init(rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public var description: String { String(rawValue) }
}

/// A render-server context whose layer tree WallpaperAgent shows on a surface:
/// the private `CAContext`, which the extension never touches itself.
///
/// Not `Sendable`: like the layers it hosts, it belongs to the main actor.
public final class RemoteContext {
    private let context: CAContext

    /// A new context on the render server, for the display the agent named if
    /// it named one. `nil` when the private class has gone or the server refused.
    public init?(display: UInt32?) {
        guard RemoteContextAPI.isPresent else { return nil }
        let options: [String: Any] = display.map { $0 == 0 ? [:] : ["displayId": $0] } ?? [:]
        guard let context = CAContext.remoteContext(options: options) as? CAContext, context.contextId != 0 else { return nil }
        self.context = context
    }

    public var id: RemoteContextID { RemoteContextID(rawValue: context.contextId) }

    /// The root of the tree the agent shows. Set it, and flush the transaction,
    /// before the acquire's reply: the agent starts hosting when it gets the reply.
    public var layer: CALayer? {
        get { context.layer }
        set { context.layer = newValue }
    }

    /// Stops the render server hosting the tree. The context is not used again.
    public func invalidate() {
        guard RemoteContextAPI.canInvalidate else { return }
        context.invalidate()
    }
}

/// What the wrapper needs of `CAContext`, looked up by name so that a macOS
/// without it fails the self-check rather than the process.
enum RemoteContextAPI {
    static let className = "CAContext"
    static let factory = NSSelectorFromString("remoteContextWithOptions:")
    static let instanceMethods = ["contextId", "layer", "setLayer:"].map(NSSelectorFromString)
    static let invalidate = NSSelectorFromString("invalidate")

    static var isPresent: Bool { hasFactory && hasAccessors }

    static var hasFactory: Bool {
        let type: AnyClass? = NSClassFromString(className)
        return (type as AnyObject?)?.responds(to: factory) ?? false
    }

    static var hasAccessors: Bool {
        let type: AnyClass? = NSClassFromString(className)
        return instanceMethods.allSatisfy { type?.instancesRespond(to: $0) ?? false }
    }

    static var canInvalidate: Bool {
        NSClassFromString(className)?.instancesRespond(to: invalidate) ?? false
    }
}
