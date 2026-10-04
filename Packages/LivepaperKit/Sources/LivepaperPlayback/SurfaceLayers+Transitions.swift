// The crossfade on two layers made up front (only the upper one's opacity animated, started once the
// incoming layer has a picture) follows the spike's SurfaceLayers, after
// Phosphene (MIT, (c) 2026 kageroumado, https://github.com/kageroumado/phosphene). See NOTICE at the
// repository root.

import LivepaperCore

extension SurfaceLayers {
    // MARK: Starting

    /// A fresh start on `slot`: with nothing showing yet, on the lower layer without a fade;
    /// otherwise a crossfade that starts once the new video has a picture.
    func start(_ wallpaper: SurfaceWallpaper, on slot: VideoSlot, _ plan: CrossfadePlan) async {
        let run = epoch
        incoming = slot
        state = .playing
        showing[slot] = Showing(wallpaper: wallpaper, size: showing[slot]?.size)
        tree.transaction { tree.apply(plan.before) }

        guard let video = await startEngine(on: slot, wallpaper, clearing: plan.clears, run) else { return }
        showing[slot]?.size = video.size
        tree.transaction { layOut() }

        if await !tree.waitUntilReady(slot) {
            logger.notice("\(EngineLog.notReadyForDisplay(self.id, video.url), privacy: .public)")
        }
        guard run == epoch else { return }
        tree.transaction {
            tree.showBackground(behindWallpaper: true)
            tree.apply(plan.whenReady)
            if let fade = plan.fade { tree.animate(fade, over: Self.crossfadeDuration) }
        }
        if plan.fade != nil {
            // The animation runs in the render server and may start a frame late.
            try? await Task.sleep(for: Self.crossfadeDuration + .milliseconds(200))
            guard run == epoch else { return }
        }

        front = slot
        incoming = nil
        if let stops = plan.stops {
            showing[stops] = nil
            await engines[stops].stop()
            guard run == epoch else { return }
        }
        releaseStill()
        if let next = queued {
            queued = nil
            await show(next.wallpaper, crossfade: next.crossfade)
        }
    }

    /// Starts the engine on `slot` on a layer cleared first when the plan says so. Nil when the
    /// surface has moved on, or when the video cannot be played and the poster is held instead.
    private func startEngine(
        on slot: VideoSlot,
        _ wallpaper: SurfaceWallpaper,
        clearing clears: VideoSlot?,
        _ run: Int
    ) async -> LoopEngine.Video? {
        if let clears {
            // A layer can still hold an earlier picture (a rebuild retires engines without
            // touching their layers), and then it would report ready at once: an engine that
            // stops takes the picture off its layer.
            await engines[clears].stop()
            guard run == epoch else { return nil }
        }
        // A redirect that came meanwhile has the last word.
        let wanted = showing[slot]?.wallpaper ?? wallpaper
        let engine = engines[slot]
        await engine.setVolume(wanted.volume)
        let video = await engine.play(wanted.video)
        guard run == epoch else { return nil }
        guard let video else {
            // A redirect may have sent the engine to another video, and that is what failed.
            incoming = nil
            await cannotPlay(showing[slot]?.wallpaper ?? wallpaper)
            return nil
        }
        return video
    }

    /// Switches the engine on `slot` in place: the front one when no fade is asked, or the first
    /// one while it is still starting.
    func switchInPlace(_ slot: VideoSlot, to wallpaper: SurfaceWallpaper) async {
        let run = epoch
        let held = state
        state = .playing
        showing[slot] = Showing(wallpaper: wallpaper, size: showing[slot]?.size)

        let engine = engines[slot]
        await engine.setVolume(wallpaper.volume)
        let video = held == .suspended ? await engine.play(wallpaper.video) : await engine.switch(to: wallpaper.video)
        if held == .paused { await engine.resume() }
        // A later request for this layer has the last word.
        guard run == epoch, showing[slot]?.wallpaper == wallpaper else { return }
        guard let video else {
            await cannotPlay(wallpaper)
            return
        }
        showing[slot]?.size = video.size
        tree.transaction { layOut() }
    }

    private func cannotPlay(_ wallpaper: SurfaceWallpaper) async {
        logger.error("\(EngineLog.cannotPlay(self.id, wallpaper.video), privacy: .public)")
        await holdStill(poster: wallpaper)
    }

    // MARK: Recovering

    func rebuildSurface() async {
        epoch += 1
        let run = epoch
        queued = nil
        replaceEngines()
        await applyMetricsProbe()
        guard run == epoch else { return }

        let held = state
        guard held == .playing || held == .paused || held == .suspended,
              let slot = front ?? incoming, let current = showing[slot] else { return }
        let other: VideoSlot = slot == .lower ? .upper : .lower
        front = slot
        incoming = nil
        showing[other] = nil
        tree.transaction {
            tree.stopFades()
            // The lower layer may stay opaque under the upper one; the upper one may not stay over the lower.
            tree.apply([OpacityChange(slot, 1)] + (other == .upper ? [OpacityChange(.upper, 0)] : []))
        }

        state = .playing
        let engine = engines[slot]
        await engine.setVolume(current.wallpaper.volume)
        let video = await engine.play(current.wallpaper.video)
        guard run == epoch else { return }
        guard let video else {
            await cannotPlay(current.wallpaper)
            return
        }
        showing[slot]?.size = video.size
        tree.transaction { layOut() }
        if held == .paused { await pause() }
        if held == .suspended { await suspend() }
    }

    func rebuildPipeline() async {
        let held = state
        let wallpaper = self.wallpaper
        epoch += 1
        queued = nil
        replaceEngines()
        await applyMetricsProbe()
        guard let wallpaper, held != .nothing else {
            await showNothing()
            return
        }
        // The poster stands in while the video starts again.
        await holdStill(poster: wallpaper)
        guard held != .still else { return }
        await show(wallpaper, crossfade: false)
        if held == .paused { await pause() }
        if held == .suspended { await suspend() }
    }

    /// The old engines are retired, not stopped: a stuck one cannot hold the recovery up.
    private func replaceEngines() {
        for engine in engines.all { engine.retire() }
        engines = VideoSlots(
            lower: LoopEngine(feed: tree.feeds.lower, logger: logger),
            upper: LoopEngine(feed: tree.feeds.upper, logger: logger)
        )
    }
}
