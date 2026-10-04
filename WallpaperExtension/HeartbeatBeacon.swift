import Foundation
import LivepaperCore
import LivepaperPlayback
import WallpaperAgentBridge

/// All the extension says to the app: a packed `Heartbeat` in the state of a
/// Darwin notification, once at launch and then every
/// `HeartbeatTiming.standard.interval`, and at once when something the app
/// waits on changes. Its timer is the only one the extension keeps running.
final class HeartbeatBeacon {
    private let supervisor: PlaybackSupervisor
    private let listener: WallpaperAgentListener
    private let selfCheckFailed: Bool
    private var lastPosted: Heartbeat?

    init(supervisor: PlaybackSupervisor, listener: WallpaperAgentListener, selfCheckFailed: Bool) {
        self.supervisor = supervisor
        self.listener = listener
        self.selfCheckFailed = selfCheckFailed
    }

    /// Beats now, and then on the interval for the life of the process. The
    /// run loop keeps the timer.
    func start() {
        post()
        let interval = HeartbeatTiming.standard.interval / .seconds(1)
        let timer = Timer(timeInterval: interval, repeats: true) { [self] _ in
            MainActor.assumeIsolated { post() }
        }
        timer.tolerance = interval / 10
        RunLoop.main.add(timer, forMode: .common)
    }

    func post() {
        let beat = current(at: Date())
        lastPosted = beat
        HostNotification.heartbeat.post(state: beat.packed)
    }

    /// Beats now if the heartbeat is not the one last sent: after an acquire
    /// or an invalidate, so that the app sees `desktopSurfaceAcquired` change
    /// without waiting for the timer.
    func postIfChanged() {
        if current(at: Date()) != lastPosted { post() }
    }

    private func current(at now: Date) -> Heartbeat {
        var beat = supervisor.heartbeat
        if selfCheckFailed { beat.flags.insert(.selfCheckFailed) }
        if listener.isSpiralling(at: now) { beat.flags.insert(.spiralDetected) }
        return beat
    }
}
