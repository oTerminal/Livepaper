import Foundation
import LivepaperCore
import os

/// Decides what every surface shows, and checks that it really shows it.
///
/// The extension owns it on its main actor and calls it only from there: it is
/// not `Sendable` and nothing in it is `@MainActor`. Each entry point takes
/// the caller's isolation, and what it starts (the timers, the watchdog's
/// checks, the calls on the surfaces) runs on that same actor. The agent and
/// the system call in from synchronous callbacks, so an entry point that has
/// work to wait on starts one task for it and returns it; the extension drops
/// it, and the tests await it. Inside that task the work is structured.
///
/// For each display it takes `decidePlayback` on the render state's
/// conditions: when a surface is acquired, when a new state lands, a second
/// after a wake, and when the conditions behind a pause expire. Every surface
/// of a display, the Settings preview included, follows that display's decision.
public final class PlaybackSupervisor {
    // Internal rather than private only so that the watchdog's extension, in
    // the file beside this one, can reach them.
    let location: LibraryLocation
    let clock: any Clock<Duration>
    let now: () -> Date
    let host: HostCapabilities
    let logger: Logger
    let tearDown: (SurfaceID) -> Void

    var store = SurfaceStore()
    var surfaces: [SurfaceID: any SurfacePlayback] = [:]
    var current = CurrentRenderState.none
    var watchdog = WatchdogSchedule()
    /// The decision last logged for each display with a live surface.
    var decisions: [DisplayIdentity: DisplayDecision] = [:]
    /// Surfaces with calls in flight, and those asked to reconcile meanwhile.
    var reconciling: Set<SurfaceID> = []
    var outdated: Set<SurfaceID> = []
    var expiry: (deadline: Date, timer: Task<Void, Never>)?
    var teardownTimer: Task<Void, Never>?
    var wakeTimer: Task<Void, Never>?
    /// Those waiting for the check that runs now to end.
    var checkEnded: [CheckedContinuation<Void, Never>] = []

    /// - Parameters:
    ///   - location: The library, to resolve the render state's paths in.
    ///   - clock: What the supervisor waits on: the teardown grace, the second
    ///     after a wake, the expiry of sensed conditions.
    ///   - now: The wall clock. The app stamps its sensed conditions with it,
    ///     so decisions are taken on it.
    ///   - tearDown: Called when a surface's grace has run out, the store's
    ///     `.tearDown` effect: the extension invalidates the surface's context
    ///     and drops it. The supervisor then releases the layer tree's decoders
    ///     with `showNothing()` and lets it go.
    public init(
        location: LibraryLocation,
        clock: any Clock<Duration>,
        now: @escaping () -> Date = { Date() },
        host: HostCapabilities = HostCapabilities(showsLockScreen: true),
        logger: Logger,
        tearDown: @escaping (SurfaceID) -> Void
    ) {
        self.location = location
        self.clock = clock
        self.now = now
        self.host = host
        self.logger = logger
        self.tearDown = tearDown
    }

    /// What the heartbeat carries from the supervisor. The extension adds
    /// `selfCheckFailed` and `spiralDetected` itself.
    public var heartbeat: Heartbeat {
        var flags: Heartbeat.Flags = []
        if store.hasLiveDesktopSurface { flags.insert(.desktopSurfaceAcquired) }
        if current.isHoldingStill { flags.insert(.holdingStill) }
        if watchdog.restartAgentRequested { flags.insert(.restartAgentRequested) }
        return Heartbeat(acknowledging: current.generation ?? 0, flags: flags)
    }

    // MARK: Surfaces

    /// What the supervisor knows of a surface: its display, whether it is the
    /// Settings preview, its mode, and whether the agent still shows it. `nil`
    /// for one it does not know, or has torn down. The extension reads it here
    /// rather than keeping its own copy.
    public func entry(for surface: SurfaceID) -> SurfaceStore.Entry? {
        store.entries[surface]
    }

    /// The agent acquired a surface. A surface the store does not know gets
    /// the layer tree `makeSurface` builds; one it knows is laid out again for
    /// `geometry`. Returns once the surface has been told what to show, with
    /// what to do about its context.
    public func acquire(
        _ surface: SurfaceID,
        display: DisplayIdentity,
        isPreview: Bool,
        geometry: SurfaceGeometry,
        makeSurface: () -> any SurfacePlayback,
        isolation: isolated (any Actor)? = #isolation
    ) async -> SurfaceStoreEffect {
        let effect = store.acquire(surface, display: display, isPreview: isPreview)
        if effect == .reuse(surface), let existing = surfaces[surface] {
            existing.layout(surface: geometry)
        } else {
            surfaces[surface] = makeSurface()
        }
        log(SupervisorLog.acquired(fields(surface), reused: effect == .reuse(surface)))
        scheduleTeardown()
        refreshDecisions()
        await reconcile(surface)
        return effect
    }

    /// The agent let go of a surface. It is kept as it is for
    /// `SurfaceStore.teardownGrace` and then torn down, unless it is acquired
    /// again. `false` for a surface the supervisor does not know.
    @discardableResult
    public func invalidate(_ surface: SurfaceID, isolation: isolated (any Actor)? = #isolation) -> Bool {
        guard store.invalidate(surface, at: now()) else {
            log(SupervisorLog.invalidatedUnknown(surface))
            return false
        }
        log(SupervisorLog.invalidated(fields(surface)))
        forgetInWatchdog(surface)
        scheduleTeardown()
        refreshDecisions()
        return true
    }

    /// The agent's `update`: where the surface is shown now. Starts a check.
    @discardableResult
    public func update(
        _ surface: SurfaceID, mode: SurfaceMode, isolation: isolated (any Actor)? = #isolation
    ) -> Task<Void, Never> {
        if store.update(surface, mode: mode) {
            log(SupervisorLog.updated(fields(surface), mode: mode))
        }
        return startCheck(.update)
    }

    /// The agent's `update` for a surface it did not name, or named in a way
    /// the bridge could not read. Something changed all the same, so the
    /// watchdog checks, for the same reason as after any update.
    @discardableResult
    public func agentUpdated(isolation: isolated (any Actor)? = #isolation) -> Task<Void, Never> {
        startCheck(.update)
    }

    /// The agent gave one surface a new size in its `update`, as it does for
    /// the Settings preview: that surface is laid out again. Nothing for a
    /// surface the supervisor does not know.
    public func layout(_ surface: SurfaceID, geometry: SurfaceGeometry) {
        surfaces[surface]?.layout(surface: geometry)
    }

    /// A display's mode changed. The agent sends nothing and stretches the old
    /// surface, so the extension watches for reconfiguration and hands
    /// the display's new geometry here: its desktop surfaces are laid out again.
    public func layout(display: DisplayIdentity, geometry: SurfaceGeometry) {
        for surface in store.liveSurfaces(on: display) where store.entries[surface]?.isPreview == false {
            surfaces[surface]?.layout(surface: geometry)
        }
    }

    // MARK: The render state

    /// A read of the render state, at launch or on `HostNotification.renderStateChanged`.
    /// The heartbeat acknowledges it as soon as this returns; the task brings the surfaces to it.
    @discardableResult
    public func apply(_ read: RenderStateRead, isolation: isolated (any Actor)? = #isolation) -> Task<Void, Never> {
        log(SupervisorLog.renderState(read, kept: current.generation))
        current = current.applying(read)
        refreshDecisions()
        return Task {
            _ = isolation
            await self.reconcileEverySurface()
        }
    }

    // MARK: Taking decisions

    /// Takes every display's decision again, and brings every surface to it.
    func reconcileAll(isolation: isolated (any Actor)? = #isolation) async {
        refreshDecisions()
        await reconcileEverySurface()
    }

    /// Brings every surface to what its display's decision says: those within
    /// their grace too, so that a stopped state releases their decoders and a
    /// re-acquire finds them up to date. The surfaces are independent, so one
    /// crossfading does not hold up another display's.
    private func reconcileEverySurface(isolation: isolated (any Actor)? = #isolation) async {
        await withDiscardingTaskGroup { group in
            for surface in store.entries.keys.sorted(by: { $0.description < $1.description }) {
                // An immediate child inherits the caller's actor, where the
                // surfaces live; an ordinary one would run off it.
                group.addImmediateTask {
                    _ = isolation
                    await self.reconcile(surface)
                }
            }
        }
    }

    /// Makes the calls that take one surface to its target. Calls on a surface
    /// never overlap: a request that arrives while they are in flight is taken
    /// up when they end, against the state as it is then.
    func reconcile(_ surface: SurfaceID) async {
        guard !reconciling.contains(surface) else {
            outdated.insert(surface)
            return
        }
        reconciling.insert(surface)
        defer { reconciling.remove(surface) }
        repeat {
            outdated.remove(surface)
            guard let playback = surfaces[surface], store.entries[surface] != nil else { return }
            let target = store.target(for: surface, in: current, location: location, host: host, now: now())
            for call in surfaceCalls(toReach: target, from: playback.state, showing: playback.wallpaper) {
                await perform(call, on: playback, surface: surface)
            }
        } while outdated.contains(surface)
    }

    private func perform(_ call: SurfaceCall, on playback: any SurfacePlayback, surface: SurfaceID) async {
        switch call {
        case .show(let wallpaper, let crossfade):
            await playback.show(wallpaper, crossfade: crossfade)
            log(SupervisorLog.nowShowing(fields(surface, wallpaper: wallpaper.wallpaper), crossfade: crossfade))
        case .holdStill(let wallpaper):
            await playback.holdStill(poster: wallpaper)
            log(SupervisorLog.holdingStill(fields(surface, wallpaper: wallpaper.wallpaper)))
        case .showNothing:
            await playback.showNothing()
            log(SupervisorLog.showingNothing(fields(surface)))
        case .pause:
            await playback.pause()
        case .resume:
            await playback.resume()
        case .suspend:
            await playback.suspend()
        }
    }

    /// Logs each display's decision when it changes, and sets the timer for
    /// the soonest moment one of them expires.
    func refreshDecisions(isolation: isolated (any Actor)? = #isolation) {
        let at = now()
        let displays = Set(store.liveSurfaces.compactMap { store.entries[$0]?.display }).sorted { $0.description < $1.description }
        var decided: [DisplayIdentity: DisplayDecision] = [:]
        for display in displays {
            let target = current.target(for: display, location: location, host: host, now: at)
            let decision = DisplayDecision(target)
            if decisions[display] != decision {
                log(SupervisorLog.decision(display: display, target: target, generation: current.generation))
            }
            decided[display] = decision
        }
        decisions = decided
        scheduleExpiry(displays.compactMap { current.expiry(for: $0, host: host, now: at) }.min())
    }

    // MARK: Timers

    /// A timer that decides again when the conditions behind a pause expire.
    private func scheduleExpiry(_ deadline: Date?, isolation: isolated (any Actor)? = #isolation) {
        guard expiry?.deadline != deadline else { return }
        expiry?.timer.cancel()
        expiry = nil
        guard let deadline else { return }
        let sleep = sleeper(until: deadline)
        let timer = Task {
            _ = isolation
            do { try await sleep() } catch { return }
            guard !Task.isCancelled else { return }
            self.expiry = nil
            await self.reconcileAll()
        }
        expiry = (deadline, timer)
    }

    /// A timer for the soonest surface whose grace runs out.
    func scheduleTeardown(isolation: isolated (any Actor)? = #isolation) {
        teardownTimer?.cancel()
        teardownTimer = nil
        guard let deadline = store.nextTeardown else { return }
        let sleep = sleeper(until: deadline)
        teardownTimer = Task {
            _ = isolation
            do { try await sleep() } catch { return }
            guard !Task.isCancelled else { return }
            self.teardownTimer = nil
            await self.tearDownExpired(at: deadline)
        }
    }

    private func tearDownExpired(at deadline: Date, isolation: isolated (any Actor)? = #isolation) async {
        let entries = store.entries
        let effects = store.tearDown(at: max(now(), deadline))
        scheduleTeardown()
        var released: [any SurfacePlayback] = []
        for case .tearDown(let surface) in effects {
            let playback = surfaces.removeValue(forKey: surface)
            // Before anything awaits, so that a re-acquire cannot come between
            // the store forgetting the surface and the extension dropping its context.
            tearDown(surface)
            if let entry = entries[surface] {
                log(SupervisorLog.tornDown(fields(surface, entry: entry, wallpaper: playback?.wallpaper?.wallpaper)))
            }
            forgetInWatchdog(surface)
            if let playback { released.append(playback) }
        }
        refreshDecisions()
        for playback in released { await playback.showNothing() }
    }

    /// Waits on the clock until the wall clock reaches `deadline`. The wait is
    /// measured when the timer starts, so a clock moved on before then still wakes it.
    func sleeper(until deadline: Date) -> () async throws -> Void {
        { [clock, now] in
            try await clock.sleep(for: .seconds(max(deadline.timeIntervalSince(now()), 0)))
        }
    }

    // MARK: Log lines

    func log(_ line: String) {
        logger.notice("\(line, privacy: .public)")
    }

    /// The fields of a line about `surface`. The wallpaper is the one given,
    /// or the one it shows, or else the one its display is assigned.
    func fields(_ surface: SurfaceID, entry: SurfaceStore.Entry? = nil, wallpaper: WallpaperID? = nil) -> SupervisorLog.Surface {
        let entry = entry ?? store.entries[surface]
        // Every line is about a surface the store knows; the zero UUID only keeps this total.
        let display = entry?.display ?? DisplayIdentity(uuid: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)))
        let assigned = current.renderState?.displays.first { $0.identity == display }?.wallpaper
        return SupervisorLog.Surface(
            surface: surface,
            display: display,
            isPreview: entry?.isPreview ?? false,
            wallpaper: wallpaper ?? surfaces[surface]?.wallpaper?.wallpaper ?? assigned,
            generation: current.generation
        )
    }
}
