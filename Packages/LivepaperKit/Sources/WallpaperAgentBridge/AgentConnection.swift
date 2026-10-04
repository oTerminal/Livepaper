// The acquire flow follows Phosphene's WallpaperXPCHandler.swift (MIT,
// (c) 2026 kageroumado, https://github.com/kageroumado/phosphene); see NOTICE at
// the repository root.

import Foundation
import os
import Synchronization
import WallpaperAgentBridgeObjC

/// The object WallpaperAgent calls on one connection. It reads each payload,
/// passes the surface calls on to the extension's handler, answers the rest
/// itself, and remembers whether anything was called at all.
final class AgentConnection: NSObject, WallpaperExtensionXPCProtocol, Sendable {
    private let listener: WallpaperAgentListener
    private let pid: Int32
    private let called = Atomic(false)

    init(listener: WallpaperAgentListener, pid: Int32) {
        self.listener = listener
        self.pid = pid
    }

    /// Whether the agent called anything on this connection.
    var served: Bool { called.load(ordering: .relaxed) }

    private func markServed() {
        called.store(true, ordering: .relaxed)
    }

    // MARK: Surfaces

    func acquire(withId anId: Any?, request: Any?, reply: @escaping @Sendable (Any?, (any Error)?) -> Void) {
        markServed()
        let identified = AgentPayload.surface(in: anId)
        let request = AgentPayload.acquire(request, surface: identified ?? UUID())
        Logger.bridge.notice("\(BridgeLog.acquire(request, identified: identified != nil), privacy: .public)")
        let gate = ReplyGate(call: "acquire")
        listener.handler.acquire(request) { contextID in
            guard gate.pass() else { return }
            guard let contextID, let object = AgentReplies.remoteContext(contextID) else {
                Logger.bridge.error("\(BridgeLog.acquireFailed(surface: request.surface), privacy: .public)")
                reply(nil, BridgeError.acquireFailed)
                return
            }
            reply(object, nil)
        }
    }

    func update(withId anId: Any?, request: Any?, reply: @escaping @Sendable ((any Error)?) -> Void) {
        markServed()
        let request = AgentPayload.update(request, surface: AgentPayload.surface(in: anId))
        Logger.bridge.notice("\(BridgeLog.update(request), privacy: .public)")
        listener.handler.update(request)
        reply(nil)
    }

    func invalidate(withId anId: Any?, reply: @escaping @Sendable ((any Error)?) -> Void) {
        markServed()
        let surface = AgentPayload.surface(in: anId)
        Logger.bridge.notice("\(BridgeLog.invalidate(surface: surface), privacy: .public)")
        if let surface { listener.handler.invalidate(surface: surface) }
        reply(nil)
    }

    func snapshot(withId anId: Any?, reply: @escaping @Sendable (Any?, (any Error)?) -> Void) {
        markServed()
        let surface = AgentPayload.surface(in: anId)
        let gate = ReplyGate(call: "snapshot")
        let neutralColour = listener.neutralColour
        listener.handler.snapshot(surface: surface) { picture in
            guard gate.pass() else { return }
            let fallback = AgentReplies.fallbackPixels
            let still = picture ?? AgentReplies.solidSurface(neutralColour, width: fallback.width, height: fallback.height)
            Logger.bridge.notice("\(BridgeLog.snapshot(surface: surface, picture: picture != nil), privacy: .public)")
            let object = still.flatMap(AgentReplies.snapshot)
            if object == nil { Logger.bridge.error("\(BridgeLog.replyUnbuilt(ReplySlot.snapshot.className), privacy: .public)") }
            reply(object, nil)
        }
    }

    // MARK: Settings

    func provideSettingsViewModels(withContentTypes types: Any?, reply: @escaping @Sendable (Any?, (any Error)?) -> Void) {
        markServed()
        let models = listener.settings.reply()
        if models == nil { Logger.bridge.error("\(BridgeLog.replyUnbuilt(SettingsEntry.replyClassName), privacy: .public)") }
        reply(models, nil)
    }

    func selectedChoicesDidChange(for anId: Any?, reply: @escaping @Sendable ((any Error)?) -> Void) {
        markServed()
        reply(nil)
    }

    func handleNotification(withNamed name: Any?, reply: @escaping @Sendable ((any Error)?) -> Void) {
        markServed()
        Logger.bridge.debug("bridge: notification \(name.map { String(describing: $0) } ?? "none", privacy: .public)")
        reply(nil)
    }

    // MARK: The rest of the protocol, answered so that nothing waits

    func addChoiceRequest(
        withChoiceRequest request: Any?,
        onBehalfOfProcess process: Any?,
        reply: @escaping @Sendable (Any?, (any Error)?) -> Void
    ) {
        markServed()
        reply(nil, nil)
    }

    func removeChoiceRequest(withChoiceRequest request: Any?, reply: @escaping @Sendable ((any Error)?) -> Void) {
        markServed()
        reply(nil)
    }

    func invokeContextMenuAction(withMenuItemID menuItemID: Any?, groupItemID: Any?, reply: @escaping @Sendable ((any Error)?) -> Void) {
        markServed()
        reply(nil)
    }

    func isChoiceDownloaded(with choiceID: Any?, reply: @escaping @Sendable (Bool, (any Error)?) -> Void) {
        markServed()
        reply(true, nil)
    }

    func download(withChoiceID choiceID: Any?, reply: @escaping @Sendable ((any Error)?) -> Void) -> Any? {
        markServed()
        reply(nil)
        return nil
    }

    func pauseDownload(for choiceID: Any?, reply: @escaping @Sendable ((any Error)?) -> Void) {
        markServed()
        reply(nil)
    }

    func cancelDownload(for choiceID: Any?, reply: @escaping @Sendable ((any Error)?) -> Void) {
        markServed()
        reply(nil)
    }

    func resumeDownload(for choiceID: Any?, reply: @escaping @Sendable ((any Error)?) -> Void) {
        markServed()
        reply(nil)
    }

    func removeDownload(for choiceID: Any?, reply: @escaping @Sendable ((any Error)?) -> Void) {
        markServed()
        reply(nil)
    }

    func migrateSelectedChoice(for anId: Any?, reply: @escaping @Sendable (Any?, (any Error)?) -> Void) {
        markServed()
        reply(nil, nil)
    }

    func migrate(from: Any?, to: Any?, reply: @escaping @Sendable ((any Error)?) -> Void) {
        markServed()
        reply(nil)
    }

    func skipShuffledContent(withId anId: Any?, reply: @escaping @Sendable ((any Error)?) -> Void) {
        markServed()
        reply(nil)
    }

    func canSkipShuffledContent(withId anId: Any?, reply: @escaping @Sendable (Bool, (any Error)?) -> Void) {
        markServed()
        reply(false, nil)
    }

    func handleDebugRequest(for request: Any?, reply: @escaping @Sendable (Any?, (any Error)?) -> Void) {
        markServed()
        reply(nil, nil)
    }
}

/// Lets one reply through to the agent, whichever answer comes first.
private final class ReplyGate: Sendable {
    private let call: String
    private let open = Atomic(true)

    init(call: String) {
        self.call = call
    }

    func pass() -> Bool {
        let passed = open.exchange(false, ordering: .acquiringAndReleasing)
        if !passed { Logger.bridge.error("\(BridgeLog.secondReply(self.call), privacy: .public)") }
        return passed
    }
}

enum BridgeError: Int, Error, CustomNSError {
    case acquireFailed = 1

    static var errorDomain: String { "app.livepaper.WallpaperAgentBridge" }
}
