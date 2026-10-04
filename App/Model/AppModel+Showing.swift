import DesignSystem
import Foundation
import LivepaperCore

// What the displays show: Set on Display, the playlist pickers, the transport,
// mute, and the wallpaper service. Pause All itself is in AppModel.swift, with
// the rest of the host's life.

extension AppModel {
    // MARK: Set on display

    /// Sets a wallpaper or a playlist where `SetOnDisplayButton` says: a
    /// display's `targetID`, or `SetOnDisplayTarget.allID`. The button's state
    /// (`setOnDisplayState(for:)`) is working until the display has it, done for
    /// 1.5 s, then idle.
    func setOnDisplay(_ assignment: Assignment, target: SetOnDisplayTarget.ID) {
        if target == SetOnDisplayTarget.allID {
            setOnAllDisplays(assignment)
        } else if let display = displays.first(where: { $0.targetID == target }) {
            set(assignment, on: display.identity)
        }
    }

    func set(_ assignment: Assignment, on display: DisplayIdentity) {
        var rng = SystemRandomNumberGenerator()
        setWithFeedback(assignment, state.assigning(assignment, to: [display], now: Date(), rng: &rng))
    }

    /// Every display, plugged in now or later, shows it.
    func setOnAllDisplays(_ assignment: Assignment) {
        var rng = SystemRandomNumberGenerator()
        setWithFeedback(assignment, state.assigningToAll(assignment, connected: displays.map(\.identity), now: Date(), rng: &rng))
    }

    /// Takes a display's own assignment away: it shows what All Displays has, or nothing.
    func unassign(_ display: DisplayIdentity) {
        commit(state: state.unassigning(display))
    }

    /// A display's playlist picker in the popover. Nil is "No Playlist", which
    /// keeps the wallpaper the display shows now.
    func choosePlaylist(_ id: PlaylistID?, for display: DisplayIdentity) {
        var rng = SystemRandomNumberGenerator()
        commit(state: state.choosingPlaylist(id, for: display, in: library, now: Date(), rng: &rng))
    }

    /// Working until the displays have it, paused there under Pause All; back to
    /// idle when it was refused. Only the latest set of an assignment speaks.
    private func setWithFeedback(_ assignment: Assignment, _ next: AppState) {
        let token = feedbackTokens[assignment, default: 0] + 1
        feedbackTokens[assignment] = token
        setOnDisplayFeedback[assignment, default: SetOnDisplayFeedback()].started()
        let applying: Task<Void, Never>?
        do {
            applying = try change(state: next)
        } catch {
            setOnDisplayFeedback[assignment]?.refused()
            return
        }
        Task {
            await applying?.value
            guard feedbackTokens[assignment] == token else { return }
            setOnDisplayFeedback[assignment]?.applied(at: Date())
            guard let idleAt = setOnDisplayFeedback[assignment]?.idleAt else { return }
            try? await Task.sleep(for: .seconds(max(idleAt.timeIntervalSinceNow, 0)))
            setOnDisplayFeedback[assignment]?.tick(at: Date())
        }
    }

    // MARK: The transport

    func togglePauseAll() {
        if isPausedAll { resumeAll() } else { pauseAll() }
    }

    /// One display's pause: its decoder is kept, so resuming is instant.
    func togglePause(on display: DisplayIdentity) {
        commit(state: state.settingPaused(!state.pausedDisplays.contains(display), for: display))
    }

    /// The next wallpaper of the playlist the display shows (`NowPlaying.canSkip`).
    func next(on display: DisplayIdentity) {
        var rng = SystemRandomNumberGenerator()
        commit(state: histories.next(on: display, in: state, library: library, now: Date(), rng: &rng))
    }

    /// Back through what the display's playlist showed this session, then back
    /// through the playlist's order.
    func previous(on display: DisplayIdentity) {
        commit(state: histories.previous(on: display, in: state, library: library))
    }

    // MARK: Mute

    /// Every display at volume 0, whatever its wallpaper's volume.
    func setMuted(_ isMuted: Bool) {
        var next = state
        next.isMuted = isMuted
        commit(state: next)
    }

    func toggleMute() {
        setMuted(!state.isMuted)
    }

    // MARK: The wallpaper service

    /// The status line's Restart, when the service is not responding: the host
    /// restarts WallpaperAgent unless it did less than `agentRestartGap` ago.
    /// The line says it is restarting, then waits for the service to answer,
    /// or says when Restart can next be tried (`ServiceRestart`).
    func restartWallpaperService() {
        guard serviceRestart.started() else { return }
        let host = services.host
        let before = host.lastAgentRestart
        AppLog.logger.notice("\(AppLog.restartAsked, privacy: .public)")
        Task {
            await host.recover(.restartAgent)
            serviceRestart.finished(lastRestartBefore: before, after: host.lastAgentRestart, at: Date())
            AppLog.logger.notice("\(AppLog.restartAnswered(self.serviceRestart.phase), privacy: .public)")
            scheduleServiceRestartTick()
        }
    }

    /// The wait for the service, and when Restart can next be tried, end on the clock.
    private func scheduleServiceRestartTick() {
        serviceRestartTick?.cancel()
        serviceRestartTick = nil
        guard let next = serviceRestart.nextTick else { return }
        serviceRestartTick = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(next.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled, let self else { return }
            serviceRestart.tick(at: Date())
            scheduleServiceRestartTick()
        }
    }

    /// "Log Playback Metrics": the extension's probe. Never kept.
    func setPlaybackMetrics(_ isOn: Bool) {
        services.setPlaybackMetrics(isOn)
    }
}
