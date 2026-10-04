import Foundation
import LivepaperCore

/// The watchdog: after a wake, an unlock, a recovery, the agent's `update` or
/// the app's `check`, it counts the pictures each surface it may judge shows
/// over `WatchdogSchedule.window`, and climbs `.flush` → `.rebuildSurface` →
/// `.rebuildPipeline` on a surface that stalls, then asks the app for
/// `.restartAgent` through the heartbeat. A surface that shows too few
/// pictures while its engine is fed as usual is not composited, which is no
/// stall. The counting runs for the checks and stops: nothing polls while
/// nothing changes.
extension PlaybackSupervisor {
    /// The Mac woke. A second later every display's decision is taken again,
    /// against each surface as it is then, and a check runs.
    @discardableResult
    public func wake(isolation: isolated (any Actor)? = #isolation) -> Task<Void, Never> {
        wakeTimer?.cancel()
        let sleep = sleeper(until: now().addingTimeInterval(WatchdogSchedule.delayAfterWake / .seconds(1)))
        let task = Task {
            _ = isolation
            do { try await sleep() } catch { return }
            guard !Task.isCancelled else { return }
            self.wakeTimer = nil
            await self.reconcileAll()
            await self.runChecks(from: .wake)
        }
        wakeTimer = task
        return task
    }

    /// The session was unlocked: a check, at once.
    @discardableResult
    public func unlock(isolation: isolated (any Actor)? = #isolation) -> Task<Void, Never> {
        startCheck(.unlock)
    }

    /// The app's `HostNotification.check`: a check, at once.
    @discardableResult
    public func check(isolation: isolated (any Actor)? = #isolation) -> Task<Void, Never> {
        startCheck(.check)
    }

    /// The app's `HostNotification.recover`: `level` runs at once on the
    /// surfaces last judged stalled, and a check follows. The app never sends
    /// `.restartAgent`, which is its own to do: for that there is nothing to
    /// run, and no task.
    @discardableResult
    public func recover(_ level: RecoveryLevel, isolation: isolated (any Actor)? = #isolation) -> Task<Void, Never>? {
        let stalled = watchdog.recoveryRequested(level)
        log(SupervisorLog.recoverRequested(level, stalled: stalled.count))
        guard level < .restartAgent else { return nil }
        let recovering = stalled.compactMap { surface in surfaces[surface].map { (surface, $0) } }
        return Task {
            _ = isolation
            for (surface, playback) in recovering {
                await playback.recover(level)
                self.log(SupervisorLog.recoveryTried(self.fields(surface), level: level))
            }
            await self.runChecks(from: .recovery)
        }
    }

    /// The task of an entry point whose only work is a check.
    func startCheck(_ trigger: WatchdogTrigger, isolation: isolated (any Actor)? = #isolation) -> Task<Void, Never> {
        Task {
            _ = isolation
            await self.runChecks(from: trigger)
        }
    }

    /// Checks for `trigger`, then for whatever came in meanwhile, until nothing
    /// is left. While another check runs, `trigger` is left with it, which then
    /// runs once more, and this returns when that has ended.
    func runChecks(from trigger: WatchdogTrigger, isolation: isolated (any Actor)? = #isolation) async {
        guard watchdog.request(trigger) else {
            await withCheckedContinuation { checkEnded.append($0) }
            return
        }
        var next: WatchdogTrigger? = trigger
        while let reason = next {
            await runCheck(reason)
            next = watchdog.finish()
        }
        let waiting = checkEnded
        checkEnded = []
        for waiter in waiting { waiter.resume() }
    }

    /// One check: every surface it may judge counts over the same window, and
    /// each takes the next step of its ladder. A recovery asks for another check.
    private func runCheck(_ trigger: WatchdogTrigger, isolation: isolated (any Actor)? = #isolation) async {
        let judged = store.liveSurfaces.filter { WatchdogSchedule.mayJudge(candidate(for: $0)) }
        log(SupervisorLog.checkStarted(trigger, judging: judged.count))
        let countings = judged.compactMap { surface in
            surfaces[surface].map { Counting(surface: surface, playback: $0, wallpaper: $0.wallpaper) }
        }
        let counts = await withTaskGroup(of: (SurfaceID, PictureCount?).self) { group in
            for counting in countings {
                // An immediate child inherits the caller's actor, where the
                // surface lives; an ordinary one would run off it.
                group.addImmediateTask {
                    _ = isolation
                    return (counting.surface, await counting.playback.displayedPictures(over: WatchdogSchedule.window))
                }
            }
            var counts: [SurfaceID: PictureCount] = [:]
            for await (surface, count) in group { counts[surface] = count }
            return counts
        }
        var recovered = false
        for counting in countings {
            let surface = counting.surface
            guard let count = counts[surface],
                  let playback = surfaces[surface],
                  // A surface that went, stopped or switched while it was counted is not judged.
                  store.entries[surface]?.isLive == true, playback.state == .playing, playback.wallpaper == counting.wallpaper
            else { continue }
            log(SupervisorLog.counted(fields(surface), count))
            let attempt = watchdog.attempts[surface, default: 0]
            let wasRequested = watchdog.restartAgentRequested
            let step = watchdog.judge(surface, count)
            log(SupervisorLog.verdict(fields(surface), step, attempt: attempt))
            switch step {
            case .healthy:
                if wasRequested, !watchdog.restartAgentRequested { log(SupervisorLog.restartRequestCleared) }
            case .notComposited:
                // Not a stall: nothing to try, and no check to follow.
                break
            case .recover(let level):
                await playback.recover(level)
                log(SupervisorLog.recoveryTried(fields(surface), level: level))
                recovered = true
            case .requestRestart:
                log(SupervisorLog.restartRequested(fields(surface)))
            }
        }
        if recovered { _ = watchdog.request(.recovery) }
    }

    /// One surface to count, and what it played when the count began.
    private struct Counting {
        let surface: SurfaceID
        let playback: any SurfacePlayback
        let wallpaper: SurfaceWallpaper?
    }

    /// A surface went: its ladder goes with it.
    func forgetInWatchdog(_ surface: SurfaceID) {
        let wasRequested = watchdog.restartAgentRequested
        watchdog.forget(surface)
        if wasRequested, !watchdog.restartAgentRequested { log(SupervisorLog.restartRequestCleared) }
    }

    /// Covered and asleep are the render state's last word, fresh or not: a
    /// display wrongly skipped misses one check, one wrongly judged climbs the ladder.
    private func candidate(for surface: SurfaceID) -> WatchdogCandidate {
        let entry = store.entries[surface]
        let conditions = current.renderState?.conditions
        let display = entry?.display
        return WatchdogCandidate(
            isLive: entry?.isLive ?? false,
            isPreview: entry?.isPreview ?? false,
            mode: entry?.mode ?? .desktop,
            state: surfaces[surface]?.state ?? .nothing,
            displayCovered: display.map { conditions?.coveredDisplays.contains($0) ?? false } ?? false,
            displayAsleep: display.map { conditions?.asleepDisplays.contains($0) ?? false } ?? false
        )
    }
}
