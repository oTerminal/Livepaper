import Foundation
import LivepaperCore
import os

nonisolated public enum ExtensionHostError: Error, Equatable {
    /// The notify centre would not register the heartbeat observer.
    case heartbeatUnobservable
}

/// The app's client for the wallpaper extension, the one render host.
///
/// It tells the extension what to show by replacing `render-state.json` and
/// posting a Darwin notification, and learns how it is from the heartbeat the
/// extension posts every `HeartbeatTiming.interval`. The status
/// comes from `HostStatusReducer`; one timer, armed only while activated, wakes
/// it when the heartbeat would expire or the ladder climb. Before an automatic
/// restart of WallpaperAgent it reads, in the same turn, what the wallpaper
/// store says of Livepaper (through `WallpaperStore`, never written here) and
/// the shared record of the last restart, which Selection writes too.
public final class ExtensionHostClient: RenderHost {
    public let capabilities = HostCapabilities(showsLockScreen: true)
    public let location: LibraryLocation
    /// The state last written, which `deactivate` writes again, stopped.
    public private(set) var lastApplied: RenderState?
    /// Whether the extension's probe is on now: what the menu's checkmark shows.
    public private(set) var isPlaybackMetricsOn = false
    /// What the user last asked for this session, which an activation puts back:
    /// a deactivate switches the probe off with the decoders, and activating again must not lose it.
    private var wantsPlaybackMetrics = false

    public var currentStatus: RenderHostStatus { reducer.status }
    public var lastHeartbeat: Heartbeat? { reducer.lastHeartbeat }
    public var lastHeartbeatAt: Date? { reducer.lastHeartbeatAt }
    public var lastAgentRestart: Date? { reducer.lastAgentRestart }

    private var reducer: HostStatusReducer
    private let notifier: any DarwinNotifying
    private let agent: any AgentRestarting
    private let restartStore: any AgentRestartStore
    private let wallpaperStore: any WallpaperStoreReading
    private let clock: any WallClock
    private let sleep: any SleepSensor
    private let logger: Logger
    /// Every change is kept for each reader: a status line may show only the
    /// latest, but a log of them wants each one, and they are few.
    private let statuses = Broadcast<RenderHostStatus>(bufferingPolicy: .unbounded)
    private var check: ScheduledCall?
    private var checkAt: Date?
    private var sleepWatch: Task<Void, Never>?

    /// - Parameters:
    ///   - location: the library, in the real home; the app is not sandboxed.
    ///   - restartStore: where the last restart of the agent is kept across launches, and by Selection.
    ///   - wallpaperStore: read before a restart for silence, to tell a Livepaper that is not selected.
    public init(
        location: LibraryLocation = LibraryLocation(home: .homeDirectory),
        timing: HeartbeatTiming = .standard,
        notifier: any DarwinNotifying = DarwinNotifier(),
        agent: any AgentRestarting = WallpaperAgentRestarter(),
        restartStore: any AgentRestartStore = DefaultsAgentRestartStore(),
        wallpaperStore: any WallpaperStoreReading = WallpaperStore(home: .homeDirectory),
        clock: any WallClock = SystemWallClock(),
        sleep: any SleepSensor = SystemSleepSensor(),
        logger: Logger = Logger(subsystem: LivepaperSystem.logSubsystem, category: HostLog.category)
    ) {
        self.location = location
        self.notifier = notifier
        self.agent = agent
        self.restartStore = restartStore
        self.wallpaperStore = wallpaperStore
        self.clock = clock
        self.sleep = sleep
        self.logger = logger
        reducer = HostStatusReducer(timing: timing)
        statuses.send(reducer.status)
    }

    /// Each read starts with the current status, then gives every change.
    public var status: AsyncStream<RenderHostStatus> {
        statuses.stream()
    }

    /// Records the launch time, listens for the heartbeat and reports `.connecting`.
    /// The playback-metrics probe starts each launch off and lasts the session: an
    /// activation after a deactivate puts it back as the user left it.
    /// The ten-minute gap runs from the last restart that any launch made.
    public func activate() async throws {
        let observing = notifier.observe(HostNotification.heartbeat) { [weak self] state in
            self?.heard(Heartbeat(packed: state))
        }
        guard observing else { throw ExtensionHostError.heartbeatUnobservable }
        watchSleep()
        postPlaybackMetrics(wantsPlaybackMetrics)
        logger.notice("\(HostLog.activated, privacy: .public)")
        handle(.activated(at: clock.now, lastAgentRestart: restartStore.lastRestart))
    }

    /// Replaces `render-state.json` atomically and tells the extension to read it.
    /// The state already written is not written again.
    public func apply(_ state: RenderState) async {
        guard state != lastApplied else { return }
        write(state)
    }

    /// `.restartAgent` restarts WallpaperAgent, if `allowAgentRestart` lets it,
    /// and returns once it is back; the other levels are posted to the extension.
    public func recover(_ level: RecoveryLevel) async {
        guard level == .restartAgent else {
            logger.notice("\(HostLog.recover(level), privacy: .public)")
            notifier.post(HostNotification.recover, state: UInt64(level.rawValue))
            return
        }
        await perform(handle(.restartRequested(at: clock.now)))?.value
    }

    /// Writes the stopped state: the last one applied, or the one on disk,
    /// stopped, with the next generation. The extension then holds each
    /// display's poster.
    public func deactivate() async {
        sleepWatch?.cancel()
        sleepWatch = nil
        notifier.stopObserving(HostNotification.heartbeat)
        if isPlaybackMetricsOn { postPlaybackMetrics(false) }
        if let last = lastApplied ?? stateOnDisk() {
            if !last.isStopped { write(last.next { $0.isStopped = true }) }
        } else {
            logger.notice("\(HostLog.nothingToStop, privacy: .public)")
        }
        handle(.deactivated)
    }

    /// Switches the extension's displayed-picture probe on or off; it then logs
    /// the metrics line every 20 loops, per surface.
    public func setPlaybackMetrics(_ on: Bool) {
        wantsPlaybackMetrics = on
        postPlaybackMetrics(on)
    }

    private func postPlaybackMetrics(_ on: Bool) {
        isPlaybackMetricsOn = on
        notifier.post(HostNotification.playbackMetrics, state: on ? 1 : 0)
        logger.notice("\(HostLog.playbackMetrics(on), privacy: .public)")
    }

    /// Asks the extension to run its watchdog's check now.
    public func requestCheck() {
        notifier.post(HostNotification.check, state: nil)
        logger.notice("\(HostLog.checkRequested, privacy: .public)")
    }

    // MARK: Reducing

    private func heard(_ heartbeat: Heartbeat) {
        perform(handle(.heartbeat(heartbeat, at: clock.now)))
    }

    private func checkDue() {
        check = nil
        checkAt = nil
        perform(handle(.tick(at: clock.now)))
    }

    private func watchSleep() {
        sleepWatch?.cancel()
        let events = sleep.updates()
        sleepWatch = Task { [weak self] in
            for await event in events {
                guard let self else { return }
                switch event {
                case .willSleep: handle(.systemWillSleep)
                case .didWake: handle(.systemDidWake(at: clock.now))
                }
            }
        }
    }

    /// Reduces an event, and answers what the reducer asks to read before an
    /// automatic restart in the same turn, so that the status said is the one it ends at.
    @discardableResult
    private func handle(_ event: HostEvent) -> [HostAction] {
        let before = reducer.status
        var actions = reducer.reduce(event)
        while let index = actions.firstIndex(where: \.isReadBeforeRestart) {
            guard case .readBeforeRestart(let reason) = actions.remove(at: index) else { break }
            let read = HostEvent.readForRestart(
                reason, store: wallpaperStore.shape().selection, lastAgentRestart: restartStore.lastRestart, at: clock.now
            )
            actions += reducer.reduce(read)
        }
        if reducer.status != before {
            logger.notice("\(HostLog.status(self.reducer.status), privacy: .public)")
            statuses.send(reducer.status)
        }
        armCheck()
        return actions
    }

    private func armCheck() {
        guard reducer.nextCheck != checkAt else { return }
        check?.cancel()
        check = nil
        checkAt = reducer.nextCheck
        guard let checkAt else { return }
        check = clock.schedule(at: checkAt) { [weak self] in self?.checkDue() }
    }

    /// Posts and logs at once; a restart runs in a task, which is returned.
    @discardableResult
    private func perform(_ actions: [HostAction]) -> Task<Void, Never>? {
        var restart: Task<Void, Never>?
        for action in actions {
            switch action {
            case .postRecover(let level):
                logger.notice("\(HostLog.silence(level), privacy: .public)")
                notifier.post(HostNotification.recover, state: UInt64(level.rawValue))
            case .recoverSkipped(let level):
                logger.notice("\(HostLog.skipped(level), privacy: .public)")
            case .restartAgent(let reason):
                restartStore.lastRestart = reducer.lastAgentRestart
                logger.notice("\(HostLog.restarting(reason), privacy: .public)")
                restart = Task { [agent, logger] in
                    let outcome = await agent.restartAgent()
                    logger.notice("\(HostLog.restarted(outcome), privacy: .public)")
                }
            case .restartRefused(let reason, let refusal):
                logger.notice("\(HostLog.refused(reason, refusal), privacy: .public)")
            case .readBeforeRestart:
                // Answered in `handle`, before the status is said.
                break
            }
        }
        return restart
    }

    // MARK: The render state

    private func write(_ state: RenderState) {
        do {
            let data = try state.encode()
            try FileManager.default.createDirectory(at: location.root, withIntermediateDirectories: true)
            try data.write(to: location.renderState, options: .atomic)
        } catch {
            logger.error("\(HostLog.renderStateNotWritten(state, error), privacy: .public)")
            return
        }
        lastApplied = state
        notifier.post(HostNotification.renderStateChanged, state: nil)
        logger.info("\(HostLog.renderStateWritten(state), privacy: .public)")
    }

    private func stateOnDisk() -> RenderState? {
        try? RenderState.decode(Data(contentsOf: location.renderState))
    }
}
