// The per-selector class whitelist is adapted from Phosphene's
// WallpaperExtensionConfig.swift (MIT, (c) 2026 kageroumado,
// https://github.com/kageroumado/phosphene); see NOTICE at the repository root.

import CoreGraphics
import Foundation
import os
import Synchronization
import WallpaperAgentBridgeObjC

/// Takes WallpaperAgent's connections to the extension. The extension makes
/// one, after `WallpaperAgentBridge.load()`, and hands it every connection its
/// `AppExtensionConfiguration` is asked to accept.
///
/// It answers the settings view models itself, from `settings`, and passes the
/// surface calls to `handler`. Connections that end without a call feed the
/// spiral detector.
public final class WallpaperAgentListener: Sendable {
    let handler: any SurfaceRequestHandler
    let settings: SettingsEntry
    /// Filled into a snapshot when the extension has no picture for the surface.
    let neutralColour: CGColor
    private let spiral = Mutex(SpiralDetector())

    public init(handler: any SurfaceRequestHandler, settings: SettingsEntry, neutralColour: CGColor) {
        self.handler = handler
        self.settings = settings
        self.neutralColour = neutralColour
    }

    /// Exports the extension's side of the protocol on `connection`, with the
    /// payload classes allowed per selector, and resumes it. For
    /// `AppExtensionConfiguration.accept(connection:)`, which returns the result.
    public func accept(_ connection: NSXPCConnection) -> Bool {
        let pid = connection.processIdentifier
        let exported = AgentConnection(listener: self, pid: pid)
        connection.exportedInterface = Self.exportedInterface()
        connection.exportedObject = exported
        connection.remoteObjectInterface = NSXPCInterface(with: (any WallpaperExtensionProxyXPCProtocol).self)
        connection.invalidationHandler = { [self] in
            connectionEnded(pid: pid, served: exported.served)
        }
        connection.resume()
        Logger.bridge.notice("\(BridgeLog.accepted(pid: pid), privacy: .public)")
        return true
    }

    /// Whether the heartbeat should carry `spiralDetected` at `now`: from the
    /// detector's signal until the agent is served again or 10 minutes pass.
    public func isSpiralling(at now: Date) -> Bool {
        spiral.withLock { $0.isSignalling(at: now) }
    }

    private func connectionEnded(pid: Int32, served: Bool) {
        let now = Date()
        let (signal, emptyInARow) = spiral.withLock { detector in
            (detector.connectionEnded(served: served, at: now), detector.emptyInARow)
        }
        Logger.bridge.notice("\(BridgeLog.ended(pid: pid, served: served, emptyInARow: emptyInARow), privacy: .public)")
        guard signal else { return }
        Logger.bridge.error("\(BridgeLog.spiral(emptyInARow: emptyInARow), privacy: .public)")
        handler.spiralDetected()
    }

    /// The extension's side of the protocol. NSXPC refuses a class it has not
    /// been told to expect in that argument of that selector, so each argument
    /// and reply that carries a payload allows the payload classes present.
    private static func exportedInterface() -> NSXPCInterface {
        let interface = NSXPCInterface(with: (any WallpaperExtensionXPCProtocol).self)
        let foundation: [AnyClass] = [
            NSString.self, NSNumber.self, NSData.self, NSArray.self, NSDictionary.self, NSURL.self, NSError.self,
        ]
        let payloads = WallpaperAgentBridge.payloadClassNames.compactMap { objc_getClass($0) as? AnyClass }
        // Class objects are NSObjects, so the set bridges; the cast cannot fail.
        guard let allowed = NSSet(array: foundation + payloads) as? Set<AnyHashable> else {
            Logger.bridge.fault("bridge: the payload classes could not be allowed")
            return interface
        }
        for slot in payloadSlots {
            interface.setClasses(allowed, for: slot.selector, argumentIndex: slot.argument, ofReply: slot.ofReply)
        }
        return interface
    }

    /// One argument of a call, or the first of its reply, that carries a payload.
    private struct Slot {
        let selector: Selector
        let argument: Int
        let ofReply: Bool

        static func of(_ selector: Selector, arguments: [Int], reply: Bool = false) -> [Slot] {
            arguments.map { Slot(selector: selector, argument: $0, ofReply: false) }
                + (reply ? [Slot(selector: selector, argument: 0, ofReply: true)] : [])
        }
    }

    private static let payloadSlots: [Slot] = {
        typealias Agent = WallpaperExtensionXPCProtocol
        return Slot.of(#selector(Agent.acquire(withId:request:reply:)), arguments: [0, 1], reply: true)
            + Slot.of(#selector(Agent.update(withId:request:reply:)), arguments: [0, 1])
            + Slot.of(#selector(Agent.invalidate(withId:reply:)), arguments: [0])
            + Slot.of(#selector(Agent.snapshot(withId:reply:)), arguments: [0], reply: true)
            + Slot.of(#selector(Agent.provideSettingsViewModels(withContentTypes:reply:)), arguments: [0], reply: true)
            + Slot.of(#selector(Agent.addChoiceRequest(withChoiceRequest:onBehalfOfProcess:reply:)), arguments: [0, 1], reply: true)
            + Slot.of(#selector(Agent.removeChoiceRequest(withChoiceRequest:reply:)), arguments: [0])
            + Slot.of(#selector(Agent.selectedChoicesDidChange(for:reply:)), arguments: [0])
            + Slot.of(#selector(Agent.invokeContextMenuAction(withMenuItemID:groupItemID:reply:)), arguments: [0, 1])
            + Slot.of(#selector(Agent.isChoiceDownloaded(with:reply:)), arguments: [0])
            + Slot.of(#selector(Agent.download(withChoiceID:reply:)), arguments: [0])
            + Slot.of(#selector(Agent.pauseDownload(for:reply:)), arguments: [0])
            + Slot.of(#selector(Agent.cancelDownload(for:reply:)), arguments: [0])
            + Slot.of(#selector(Agent.resumeDownload(for:reply:)), arguments: [0])
            + Slot.of(#selector(Agent.removeDownload(for:reply:)), arguments: [0])
            + Slot.of(#selector(Agent.migrateSelectedChoice(for:reply:)), arguments: [0], reply: true)
            + Slot.of(#selector(Agent.migrate(from:to:reply:)), arguments: [0, 1])
            + Slot.of(#selector(Agent.skipShuffledContent(withId:reply:)), arguments: [0])
            + Slot.of(#selector(Agent.canSkipShuffledContent(withId:reply:)), arguments: [0])
            + Slot.of(#selector(Agent.handleDebugRequest(for:reply:)), arguments: [0], reply: true)
            + Slot.of(#selector(Agent.handleNotification(withNamed:reply:)), arguments: [0])
    }()
}
