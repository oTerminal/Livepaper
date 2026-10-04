import DesignSystem
import Foundation
import LivepaperCore
import LivepaperImport
import LivepaperSystem
import Observation

/// The app's one model: the library, the app state, and what is only held
/// while the app runs. Every screen reads it and calls its actions; none sets
/// its properties.
///
/// It is the one writer of `library.json` and `app-state.json`, and, through
/// the render host, of `render-state.json`. Each change is saved, then the
/// displays follow in one render state (`RenderState.make`), the states
/// applied one after another. Every decision is Core's or Import's; the model
/// calls them and carries out what they answer.
///
/// This file holds what is kept and the life of the app (launch, Pause All,
/// quit) and the one way a change is made (`commit`). The screens' values are
/// in AppModel+Screens.swift and the actions in the other AppModel+ files.
/// `@MainActor` is written out: conforming to `ImportLibrary`, a `Sendable`
/// protocol, takes a type out of the target's default main-actor isolation.
@MainActor @Observable
final class AppModel: ImportLibrary {
    // MARK: What is kept

    /// Saved before a change to it counts.
    private(set) var library = Library()
    /// Changes count at once and are saved as they happen.
    private(set) var state = AppState()
    /// Set when the library could not be read at launch. Nothing is written
    /// then, so a library a newer Livepaper wrote, or a damaged one, is left as
    /// it is, and the displays keep what the last run left them.
    private(set) var libraryProblem: LibraryProblem?

    // MARK: The displays and the host

    /// In the order the display sensor lists them.
    private(set) var displays: [Display] = []
    private(set) var hostStatus: RenderHostStatus = .stopped
    /// Pause All: every display paused in place, as its own pause does. Not
    /// remembered: the next launch is live.
    private(set) var isPausedAll = false
    /// The render state made last.
    private(set) var renderState: RenderState?
    private(set) var conditions: SensedConditions?

    // MARK: The library window, set only by the model's actions

    private var sectionValue = LibrarySection.all
    private var searchValue = ""
    private var toastPresenter = ToastPresenter()
    /// The one selected tile.
    var selection = GridSelection()
    var importList = ImportList()
    /// Set on Display's feedback, per wallpaper or playlist being set.
    var setOnDisplayFeedback: [Assignment: SetOnDisplayFeedback] = [:]
    /// Presentation and volume edits the inspector is making: the preview
    /// follows them at once, the library and the displays once they settle.
    var drafts: [WallpaperID: WallpaperDraft] = [:]

    /// Posters and the files previews play, in either run.
    let art: WallpaperArt
    /// The login item, the hotkeys and leaving Livepaper, for Settings.
    let systemServices: any SystemServices

    // MARK: Plumbing

    @ObservationIgnored let services: AppServices
    @ObservationIgnored private(set) var isLaunched = false
    @ObservationIgnored private(set) var isQuitting = false
    /// Displays are known once the sensor has spoken. Until then no render state
    /// is made: it would show nothing on every display.
    @ObservationIgnored private(set) var areDisplaysKnown = false
    @ObservationIgnored private(set) var sensing: ConditionsSensing?
    /// Made once the launch has swept: observed, so Import is offered then.
    private(set) var importer: (any ImportRunning)?
    /// Work that goes on beside the app, the scenes' preparation among it, cancelled at quit.
    @ObservationIgnored var watches: [Task<Void, Never>] = []
    @ObservationIgnored private(set) var launching: Task<Void, Never>?
    @ObservationIgnored private var quitting: Task<Void, Never>?
    /// Render states are applied in the order they were made, each after the one before.
    @ObservationIgnored private var applying: Task<Void, Never>?
    /// The live state made last, and the one last handed to the host: a state is
    /// whole, so one made while another waited to be applied replaces it.
    @ObservationIgnored private var madeLast: RenderState?
    @ObservationIgnored private var handedToHost: RenderState?
    /// What each display's playlist showed this session, for Previous.
    @ObservationIgnored var histories = RotationHistories()
    @ObservationIgnored var pendingDeletion: PendingDeletion?
    @ObservationIgnored var runningImport: (id: UUID, task: Task<Void, Never>)?
    /// Rows being looked for in the library before their turn (`ImportList.Effect.check`).
    @ObservationIgnored var importChecks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored var importTick: Task<Void, Never>?
    @ObservationIgnored var settling: [WallpaperID: Task<Void, Never>] = [:]
    /// Moves on with each set, so that only the latest one's apply says done.
    @ObservationIgnored var feedbackTokens: [Assignment: Int] = [:]
    /// Moves each display's playlist on (AppModel+Rotation.swift).
    @ObservationIgnored var rotationDriver: RotationDriver?
    /// What came of the status line's Restart, and the clock that ends its waits.
    var serviceRestart = ServiceRestart()
    @ObservationIgnored var serviceRestartTick: Task<Void, Never>?

    init(services: AppServices) {
        self.services = services
        art = WallpaperArt(services.art)
        systemServices = services.systemServices
    }

    // MARK: The library window's bindings

    /// The sidebar's selection.
    var section: LibrarySection {
        get { sectionValue }
        set {
            sectionValue = newValue
            selection.sectionChanged(to: newValue, grid: grid.map(\.id))
        }
    }

    /// The toolbar's search field.
    var search: String {
        get { searchValue }
        set {
            searchValue = newValue
            gridDidChange()
        }
    }

    /// The one toast, which the library window's `toastHost` binds to: the host
    /// expires and dismisses it through this, and hands an undo to `undo(_:)`.
    var toasts: ToastPresenter {
        get { toastPresenter }
        set {
            toastPresenter = newValue
            toastsDidChange()
        }
    }
}

// The life of the app and the one way a change is made. Here, in the class's
// own file, because only this file sets what is kept.
extension AppModel {
    // MARK: Launch

    /// Reads what was kept, starts the host and the sensors, and shows it. Once.
    func launch() {
        guard launching == nil else { return }
        launching = Task { await start() }
    }

    private func start() async {
        AppLog.logger.notice("\(AppLog.launched(fakes: self.services.isFakes), privacy: .public)")
        load()
        services.system.start(state, self)
        makeRotationDriver()
        prepareScenes()
        watchHostStatus()
        do {
            try await services.host.activate()
        } catch {
            AppLog.logger.error("\(AppLog.activationFailed(error), privacy: .public)")
        }
        guard !isQuitting else { return }
        let sensing = services.makeSensing(state.pauseRules) { [weak self] conditions in
            self?.sensed(conditions)
        }
        self.sensing = sensing
        watchDisplays(sensing.displays)
        sensing.start()
        isLaunched = true
        applyRenderState()
    }

    /// What the launch reads, in order, before anything is shown or imported.
    private func load() {
        // Before any import is accepted: what a killed import left goes first.
        do {
            let swept = try services.sweep()
            AppLog.logger.notice("\(AppLog.swept(swept.count), privacy: .public)")
        } catch {
            AppLog.logger.error("\(AppLog.sweepFailed(error), privacy: .public)")
        }
        do {
            library = try services.libraryStore.load()
        } catch {
            libraryProblem = .unreadable
            AppLog.logger.error("\(AppLog.libraryUnreadable(error), privacy: .public)")
        }
        switch services.appStateStore.load() {
        case .loaded(let kept):
            state = kept
        case .missing:
            break
        case .keptAside(let url, let version):
            AppLog.logger.error("\(AppLog.stateKeptAside(at: url, version: version), privacy: .public)")
        }
        // The next state carries on the generation the extension last read; one that cannot be read is logged.
        do {
            renderState = try services.lastRenderState()
        } catch {
            AppLog.logger.error("\(AppLog.renderStateUnreadable(error), privacy: .public)")
        }
        importer = services.makeImporter(self)
    }

    private func watchHostStatus() {
        let statuses = services.host.status
        watches.append(Task { [weak self] in
            for await status in statuses {
                self?.hostStatus = status
                self?.serviceRestart.hostChanged(to: status)
            }
        })
    }

    private func watchDisplays(_ sensor: any DisplaySensor) {
        let updates = sensor.updates()
        watches.append(Task { [weak self] in
            for await connected in updates {
                self?.displaysChanged(connected)
            }
        })
    }

    private func displaysChanged(_ connected: [ConnectedDisplay]) {
        displays = connected.map { Display(identity: $0.identity, name: services.displayName($0), pixelSize: $0.pixelSize) }
        let isFirst = !areDisplaysKnown
        areDisplaysKnown = true
        resolveSection()
        rotationFollowsDisplays(isFirst: isFirst)
        applyRenderState()
    }

    private func sensed(_ conditions: SensedConditions) {
        self.conditions = conditions
        applyRenderState()
    }

    /// A preview's model: the fakes' displays and a host status, set at once,
    /// without starting the host or the sensors.
    func prepareForPreview(displays connected: [ConnectedDisplay], hostStatus: RenderHostStatus) {
        load()
        self.hostStatus = hostStatus
        displaysChanged(connected)
        isLaunched = true
        applyRenderState()
    }

    // MARK: Pause All

    /// Every display pauses in place, as its own pause does: its picture held
    /// and its decoder kept, so Resume All is instant. Not remembered, so the
    /// next launch is live; stopping is Quit's alone.
    func pauseAll() {
        guard isLaunched, !isPausedAll, !isQuitting, libraryProblem == nil else { return }
        isPausedAll = true
        updateRotation()
        applyRenderState()
        AppLog.logger.notice("\(AppLog.pausedAll(generation: self.renderState?.generation), privacy: .public)")
    }

    /// At once: each display plays again, or stays paused on its own.
    func resumeAll() {
        guard isPausedAll, !isQuitting else { return }
        isPausedAll = false
        updateRotation()
        applyRenderState()
        AppLog.logger.notice("\(AppLog.resumedAll, privacy: .public)")
    }

    // MARK: Quit

    /// Writes the stopped state, in which each display holds its poster, and
    /// returns once it is written. Nothing is applied after.
    /// A delete whose undo is still up leaves its folder for the next launch's sweep.
    func quit() async {
        if let quitting { return await quitting.value }
        isQuitting = true
        let stopping = Task { await stop() }
        quitting = stopping
        await stopping.value
    }

    private func stop() async {
        await launching?.value
        stopRotationAndRestart()
        // Edits in progress are kept; the displays have them at the next launch.
        settleDrafts()
        runningImport?.task.cancel()
        importChecks.values.forEach { $0.cancel() }
        importTick?.cancel()
        sensing?.stop()
        for watch in watches {
            watch.cancel()
        }
        watches = []
        await applying?.value
        await services.host.deactivate()
        AppLog.logger.notice("\(AppLog.quit(lastGeneration: self.renderState?.generation), privacy: .public)")
    }

    // MARK: Making a change

    /// Makes a change to the library, the app state or both. The library is
    /// saved before it counts, so a change that cannot be saved is not made; the
    /// app state counts at once, and lasts until quit if it cannot be saved.
    /// The displays then follow in one render state. Answers whether it was made.
    @discardableResult
    func commit(library newLibrary: Library? = nil, state newState: AppState? = nil) -> Bool {
        do { try change(library: newLibrary, state: newState) } catch { return false }
        return true
    }

    /// `commit`, for what must hear that a change was refused (an import's insert, a delete,
    /// Set on Display's feedback). Answers the apply that carries it to the displays; nil
    /// when it is saved and they have it later (before the launch has read them).
    @discardableResult
    func change(library newLibrary: Library? = nil, state newState: AppState? = nil) throws -> Task<Void, Never>? {
        if let libraryProblem { throw libraryProblem }
        guard hasStarted else { throw refusedBeforeStart() }
        if let newLibrary, newLibrary != library {
            do {
                try services.libraryStore.save(newLibrary)
            } catch {
                AppLog.logger.error("\(AppLog.librarySaveFailed(error), privacy: .public)")
                throw error
            }
            library = newLibrary
        }
        if let newState, newState != state {
            let before = state
            state = newState
            do {
                try services.appStateStore.save(newState)
            } catch {
                AppLog.logger.error("\(AppLog.stateSaveFailed(error), privacy: .public)")
            }
            histories.forget(changedFrom: before, to: newState)
            updateRotation()
        }
        resolveSection()
        gridDidChange()
        return applyRenderState()
    }

    /// Makes the render state for what is kept now and hands it to the host,
    /// after the one before it, every display paused while paused all. Nothing
    /// is made before the launch has read the displays, while quitting, or while
    /// the library could not be read.
    ///
    /// Answers the apply that carries what is kept now: a new one, or the one
    /// still running when nothing has changed; nil when nothing is applied now.
    @discardableResult
    func applyRenderState() -> Task<Void, Never>? {
        guard isLaunched, areDisplaysKnown, !isQuitting, libraryProblem == nil else { return nil }
        guard let next = RenderState.make(
            library: library,
            state: state,
            connected: displays.map(\.identity),
            conditions: conditions,
            isPausedAll: isPausedAll,
            previous: renderState
        ) else { return applying }
        renderState = next
        madeLast = next
        AppLog.logger.info("\(AppLog.applied(next), privacy: .public)")
        return enqueue { [weak self] host in
            // The newest state by the time this one's turn comes; a later turn finds it handed over already.
            guard let self, let latest = madeLast, latest != handedToHost else { return }
            handedToHost = latest
            await host.apply(latest)
        }
    }

    /// Runs `work` on the host after everything handed to it before.
    @discardableResult
    private func enqueue(_ work: @escaping (any RenderHost) async -> Void) -> Task<Void, Never> {
        let previous = applying
        let host = services.host
        let task = Task {
            await previous?.value
            await work(host)
        }
        applying = task
        return task
    }

    /// A delete's toast ended without its undo: expired, dismissed, replaced, or
    /// its window closed. Undo takes the toast down and then asks for the undo,
    /// in the same turn, so the Trash waits for the turn to end.
    private func toastsDidChange() {
        guard let pending = pendingDeletion, toastPresenter.current?.id != pending.toast else { return }
        Task { finishDeletion(ifStill: pending.toast) }
    }
}
