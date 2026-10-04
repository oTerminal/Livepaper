import Foundation
import LivepaperCore
import LivepaperPlayback

/// What the app tells the extension, each a Darwin notification:
/// a new render state, a recovery to try, a check to run, the metrics probe.
/// The render state and the probe are also read at launch, with no app needed.
final class AppNotifications {
    private let reader: RenderStateReader
    private let supervisor: PlaybackSupervisor
    private let hosted: HostedSurfaces
    private let beacon: HeartbeatBeacon
    private var observations: [DarwinObservation] = []

    init(reader: RenderStateReader, supervisor: PlaybackSupervisor, hosted: HostedSurfaces, beacon: HeartbeatBeacon) {
        self.reader = reader
        self.supervisor = supervisor
        self.hosted = hosted
        self.beacon = beacon
    }

    /// Reads what the app last said, then listens. The beacon's first beat,
    /// which follows, acknowledges the render state read here.
    func start() {
        supervisor.apply(reader.read())
        setMetricsProbe(state: HostNotification.playbackMetrics.currentState() ?? 0)
        observe(HostNotification.renderStateChanged) { [weak self] _ in self?.applyRenderState() }
        observe(HostNotification.recover) { [weak self] state in self?.recover(state: state) }
        observe(HostNotification.check) { [weak self] _ in self?.check() }
        observe(HostNotification.playbackMetrics) { [weak self] state in self?.setMetricsProbe(state: state) }
    }

    /// Reads `render-state.json` again and hands it to the supervisor, then
    /// beats, so that the app sees the new generation acknowledged without waiting.
    private func applyRenderState() {
        supervisor.apply(reader.read())
        beacon.post()
    }

    /// The state is a `RecoveryLevel`'s raw value. `.restartAgent` is the app's
    /// own and never sent; it and anything unknown are logged and left.
    private func recover(state: UInt64) {
        guard let raw = Int(exactly: state), let level = RecoveryLevel(rawValue: raw), level < .restartAgent else {
            ExtensionLog.notice(.recoverIgnored(state: state))
            return
        }
        ExtensionLog.notice(.recoverReceived(level))
        supervisor.recover(level)
    }

    private func check() {
        ExtensionLog.notice(.checkReceived)
        supervisor.check()
    }

    /// State 1 is on, anything else off.
    private func setMetricsProbe(state: UInt64) {
        let on = state == 1
        if hosted.setMetricsProbe(on) {
            ExtensionLog.notice(.metricsProbe(on))
        }
    }

    /// The observation is kept for the life of this object; the handler is
    /// weak on it because the notification system holds the handler.
    private func observe(_ notification: DarwinNotification, _ handler: @escaping @MainActor @Sendable (UInt64) -> Void) {
        let observation = notification.observe(on: .main) { state in
            MainActor.assumeIsolated { handler(state) }
        }
        guard let observation else {
            ExtensionLog.error(.cannotObserve(notification.name))
            return
        }
        observations.append(observation)
    }
}
