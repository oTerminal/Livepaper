import AppKit
import Foundation
import LivepaperPlayback

/// The Mac waking and the session being unlocked, the moments after which
/// the supervisor decides again and its watchdog checks.
final class SystemEvents {
    private static let screenIsUnlocked = Notification.Name("com.apple.screenIsUnlocked")

    private let supervisor: PlaybackSupervisor
    private var tokens: [any NSObjectProtocol] = []

    init(supervisor: PlaybackSupervisor) {
        self.supervisor = supervisor
    }

    /// The handlers are weak on this object, which keeps the tokens that keep them.
    func start() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(NSWorkspace.didWakeNotification, in: workspace) { [weak self] in self?.woke(.system) }
        observe(NSWorkspace.screensDidWakeNotification, in: workspace) { [weak self] in self?.woke(.displays) }
        observe(Self.screenIsUnlocked, in: DistributedNotificationCenter.default()) { [weak self] in self?.unlocked() }
    }

    /// Both wakes may come for one lid cycle; the supervisor takes the later.
    private func woke(_ source: ExtensionLog.Line.WakeSource) {
        ExtensionLog.notice(.woke(source))
        supervisor.wake()
    }

    private func unlocked() {
        ExtensionLog.notice(.unlocked)
        supervisor.unlock()
    }

    private func observe(_ name: Notification.Name, in center: NotificationCenter, _ handler: @escaping @MainActor @Sendable () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { handler() }
        }
        tokens.append(token)
    }
}
