import Foundation
import LivepaperCore
import os

/// Where Selection learns what the render host reports: only the heartbeat's `.live` says that
/// Livepaper is the wallpaper. `ExtensionHostClient` is the real one.
public protocol HostStatusSource: AnyObject {
    var currentStatus: RenderHostStatus { get }
    /// Starts with the current status, then gives every change.
    var status: AsyncStream<RenderHostStatus> { get }
}

extension ExtensionHostClient: HostStatusSource {}

/// Makes Livepaper the system wallpaper, or leaves it: the onboarding card's
/// step 3 and Settings' "Stop using Livepaper as wallpaper".
///
/// `SelectionReducer` decides; this performs what it asks, through the injected store,
/// pluginkit, agent, pane and host, and feeds their answers back with the clock's time. Its
/// log lines (`SelectionLog`, category `selection`) say the store written, the agent restarted,
/// how long `.live` took, and each fallback and why.
///
/// The agent restart here is not held to `agentRestartGap`: it is what makes the edit take
/// effect, and it comes once per select or leave, which the user asks for, never in a loop. It
/// is one signal and a wait, never a burst. It is recorded in the
/// `AgentRestartStore` before the signal, as the host's own restarts are. The host reads that
/// record when it activates and again before each automatic restart, so it counts its ten
/// minutes from this one whether it is running or activates later (a relaunch after leaving):
/// a select that has not yet brought a heartbeat is not followed by a second restart.
public final class Selection {
    private var reducer = SelectionReducer()
    private let host: any HostStatusSource
    private let store: any WallpaperStoreEditing
    private let extensions: any ExtensionListing
    private let agent: any AgentRestarting
    private let restartStore: any AgentRestartStore
    private let pane: any WallpaperPaneOpening
    private let clock: any WallClock
    private let logger: Logger
    private let outcomeChanges = Broadcast<SelectionOutcome>(bufferingPolicy: .unbounded)
    private var hostWatch: Task<Void, Never>?
    private var timeout: ScheduledCall?
    private var timeoutAt: Date?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// - Parameters:
    ///   - host: the render host, whose heartbeat says when it worked.
    ///   - restartStore: where the host keeps its last agent restart; this one's goes there too.
    public init(
        host: any HostStatusSource,
        store: any WallpaperStoreEditing = WallpaperStore(home: .homeDirectory),
        extensions: any ExtensionListing = PluginKit(),
        agent: any AgentRestarting = WallpaperAgentRestarter(),
        restartStore: any AgentRestartStore = DefaultsAgentRestartStore(),
        pane: any WallpaperPaneOpening = WallpaperPane(),
        clock: any WallClock = SystemWallClock(),
        logger: Logger = Logger(subsystem: LivepaperSystem.logSubsystem, category: SelectionLog.category)
    ) {
        self.host = host
        self.store = store
        self.extensions = extensions
        self.agent = agent
        self.restartStore = restartStore
        self.pane = pane
        self.clock = clock
        self.logger = logger
        outcomeChanges.send(reducer.outcome)
    }

    public var outcome: SelectionOutcome { reducer.outcome }

    /// Each read starts with the current outcome, then gives every change: after the pane
    /// opens, the user's click there still turns it to `.selected`.
    public var outcomes: AsyncStream<SelectionOutcome> {
        outcomeChanges.stream()
    }

    /// Makes Livepaper the system wallpaper. Returns once it is `.selected`, or the pane is
    /// open for the user's click (or could not be opened), and goes on waiting for `.live`
    /// after that. A call while one runs joins it.
    @discardableResult
    public func select() async -> SelectionOutcome {
        if !reducer.isBusy {
            let status = host.currentStatus
            log(SelectionLog.selecting(host: status))
            watchHost()
            perform(handle(.select(at: clock.now, host: status)))
        }
        await settled()
        return outcome
    }

    /// Puts the previous wallpaper back. Returns once it is `.left`, or the pane is open for
    /// the user to choose another. A call while one runs joins it.
    @discardableResult
    public func leave() async -> SelectionOutcome {
        if !reducer.isBusy {
            log(SelectionLog.leaving)
            perform(handle(.leave))
        }
        await settled()
        return outcome
    }

    // MARK: Reducing

    @discardableResult
    private func handle(_ event: SelectionEvent) -> [SelectionEffect] {
        let before = reducer.outcome
        let effects = reducer.reduce(event)
        if reducer.outcome != before { outcomeChanges.send(reducer.outcome) }
        armTimeout()
        if !reducer.awaitsLive { stopWatchingHost() }
        if reducer.outcome != .working { resumeWaiters() }
        return effects
    }

    private func perform(_ effects: [SelectionEffect]) {
        for effect in effects {
            switch effect {
            case .checkListed: checkListed()
            case .writeSelection: write(selecting: true)
            case .writeDeselection: write(selecting: false)
            case .restartAgent: restartAgent()
            case .openPane(let why): openPane(why)
            case .removeKeptCopy:
                store.removeKeptCopy()
                log(SelectionLog.keptCopyRemoved)
            case .reportLive(let after): log(SelectionLog.live(after: after))
            case .reportAlreadyLive: log(SelectionLog.alreadyLive)
            }
        }
    }

    /// The store edit is a small file read and written at once, so it runs here, in the turn.
    private func write(selecting: Bool) {
        let result: Result<WallpaperStoreEdit, WallpaperStoreError>
        do throws(WallpaperStoreError) {
            let edit = selecting ? try store.select(at: clock.now) : try store.deselect()
            log(selecting ? SelectionLog.selected(edit) : SelectionLog.deselected(edit))
            result = .success(edit)
        } catch {
            result = .failure(error)
        }
        perform(handle(.edited(result)))
    }

    private func openPane(_ why: SelectionFallback) {
        log(SelectionLog.fallback(why))
        let opened = pane.openWallpaperPane()
        if !opened { log(SelectionLog.paneNotOpened) }
        perform(handle(.paneOpened(opened)))
    }

    private func checkListed() {
        Task { [weak self, extensions] in
            let listed = await extensions.isListed(WallpaperExtensionIdentity.bundleIdentifier)
            guard let self else { return }
            log(SelectionLog.listed(listed))
            perform(handle(.listed(listed)))
        }
    }

    private func restartAgent() {
        restartStore.lastRestart = clock.now
        log(SelectionLog.restarting)
        Task { [weak self, agent] in
            let outcome = await agent.restartAgent()
            guard let self else { return }
            log(SelectionLog.restarted(outcome))
            perform(handle(.agentRestarted(outcome)))
        }
    }

    private func watchHost() {
        guard hostWatch == nil else { return }
        let statuses = host.status
        hostWatch = Task { [weak self] in
            for await status in statuses {
                guard let self else { return }
                perform(handle(.host(status, at: clock.now)))
            }
        }
    }

    private func stopWatchingHost() {
        hostWatch?.cancel()
        hostWatch = nil
    }

    private func armTimeout() {
        guard reducer.deadline != timeoutAt else { return }
        timeout?.cancel()
        timeout = nil
        timeoutAt = reducer.deadline
        guard let timeoutAt else { return }
        timeout = clock.schedule(at: timeoutAt) { [weak self] in
            guard let self else { return }
            timeout = nil
            self.timeoutAt = nil
            perform(handle(.tick(at: clock.now)))
        }
    }

    private func settled() async {
        guard outcome == .working else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    private func resumeWaiters() {
        let waiting = waiters
        waiters.removeAll()
        for waiter in waiting { waiter.resume() }
    }

    private func log(_ line: String) {
        logger.notice("\(line, privacy: .public)")
    }
}
