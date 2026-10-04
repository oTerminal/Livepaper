// Starting and stopping the gapless loop. Adapted from Phosphene's VideoRenderer.swift (MIT, (c) 2026
// kageroumado, https://github.com/kageroumado/phosphene) by way of the spike's LoopEngine. See NOTICE
// at the repository root.

import AVFoundation

extension LoopEngine {
    // MARK: Starting

    func request(_ url: URL) async {
        switch switches.handle(.request(url)) {
        case .none: await settled()
        case .flush: await flushAndStart()
        case .start(let url): await start(url)
        }
    }

    /// Starts `url` from its first frame on a fresh timeline, from a fresh reader.
    func start(_ url: URL) async {
        generation += 1
        let run = generation
        startingRun = run
        defer {
            if startingRun == run { startingRun = nil }
            settleIfIdle()
        }
        haltFeeding()

        if media?.video.url != url {
            media = nil
            video = nil
            tally = EngineTally()
            ledger = PassLedger(frameDuration: ledger.frameDuration)
            do {
                let loaded = try await LoopMedia.load(url)
                guard run == generation else { return }
                media = loaded
            } catch {
                guard run == generation else { return }
                cannotPlay(EngineLog.cannotRead(url, error))
                return
            }
            if metricsSubject != nil { probe.measureGaps(frameDuration: media?.video.frameDuration) }
        }
        if volume > 0, !audioBroken {
            await loadAudioTrack()
            guard run == generation else { return }
        }
        guard let media else { return }
        begin(media, run)
    }

    /// The part of a start that does not wait: nothing can come between the flush and the first frame.
    private func begin(_ media: LoopMedia, _ run: Int) {
        // Whatever an earlier engine or an earlier start left on the layer is stamped on another timeline.
        guard onLayer({ $0.flushQueued() }) != nil else { return }
        observeRenderer()
        tally.fold(ledger)
        ledger = PassLedger(frameDuration: media.frameDuration)

        let pass: ReaderPass
        do {
            pass = try ReaderPass(reading: media, withAudio: wantsAudio)
        } catch {
            cannotPlay(EngineLog.cannotRead(media.video.url, error))
            return
        }
        guard let first = enqueueFirstFrame(from: pass) else {
            pass.cancel()
            // Retired while the first frame was read: there is nothing to report.
            if !isRetired { cannotPlay(EngineLog.passWithoutFrames(media.video.url)) }
            return
        }
        videoPass = pass
        video = media.video
        // Time and rate in one call: the synchroniser updates its timebase asynchronously.
        let rate: Float = isPaused ? 0 : 1
        onLayer { $0.synchroniser.setRate(rate, time: first) }
        probe.interruptGaps()
        troubles.feeding()
        feedVideo(run)
        if pass.audio != nil { moveAudio(to: pass, run) } else { dropAudio() }
        openNextPassLater(run)
    }

    /// A video that cannot be played leaves the engine as if nothing had been asked, so that
    /// asking again tries again.
    private func cannotPlay(_ line: String) {
        logger.error("\(line, privacy: .public)")
        tally.failures += 1
        switches = SwitchCoalescer()
        media = nil
        video = nil
    }

    func flushAndStart() async {
        generation += 1
        let run = generation
        startingRun = nil
        haltFeeding()
        probe.interruptGaps()
        // The picture on screen stays until the first new frame replaces it, so there is no black.
        await flushRenderer(removingImage: false)
        guard run == generation else { return }
        let action = switches.handle(.flushEnded)
        guard lifecycle == .running, case .start(let url) = action else {
            settleIfIdle()
            return
        }
        await start(url)
    }

    /// Waits until no switch is flushing and no start is under way.
    func settled() async {
        guard switches.isFlushing || startingRun != nil else { return }
        await withCheckedContinuation { settleWaiters.append($0) }
    }

    func settleIfIdle() {
        guard !switches.isFlushing, startingRun == nil else { return }
        let waiters = settleWaiters
        settleWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
    }

    // MARK: Stopping

    /// Stops reading and feeding. The layer keeps its picture.
    func haltFeeding() {
        rampTask?.cancel()
        rampTask = nil
        onLayer { access in
            access.renderer.stopRequestingMediaData()
            access.synchroniser.rate = 0
            access.audio?.stopRequestingMediaData()
        }
        releaseReaders()
    }

    func releaseReaders() {
        for pass in [videoPass, audioPass, nextPass] { pass?.cancel() }
        videoPass = nil
        audioPass = nil
        nextPass = nil
        audioWaitsForVideo = false
    }

    /// A retired engine's own cleanup: its readers, its probe and what it listened to. The
    /// layer's renderer and clock are behind a closed gate, and its audio came off with the close.
    func windDown() {
        generation += 1
        startingRun = nil
        lifecycle = .stopped
        switches = SwitchCoalescer()
        rampTask?.cancel()
        rampTask = nil
        releaseReaders()
        rendererObservation = nil
        probe.measureGaps(frameDuration: nil)
        metricsSubject = nil
        media = nil
        video = nil
        settleIfIdle()
    }

    /// Flushes the layer's renderer and gives back what `halt` does not keep. The decoder goes
    /// after a flush, so that the release frame is all the renderer has left to decode, and the
    /// picture after the decoder: a picture taken off first comes back with the release frame.
    func letGo(_ halt: Halt) async {
        let run = generation
        await flushRenderer(removingImage: false)
        // A start that came in meanwhile has the layer, its decoder and its picture now.
        guard run == generation else { return }
        if !halt.keeps.decoder { onLayer { $0.releaseDecoder() } }
        if !halt.keeps.picture { await flushRenderer(removingImage: true) }
    }

    func flushRenderer(removingImage: Bool) async {
        await withCheckedContinuation { continuation in
            let once = ResumeOnce(continuation)
            guard onLayer({ $0.renderer.flush(removingDisplayedImage: removingImage) { once.resume() } }) != nil else {
                once.resume()
                return
            }
            queue.asyncAfter(deadline: .now() + Self.flushTimeout) { once.resume() }
        }
    }

    // MARK: Rate

    func ramp(to target: Float) {
        rampTask?.cancel()
        rampTask = nil
        guard let from = onLayer({ $0.synchroniser.rate }) else { return }
        rampTask = Task { await self.runRamp(from: from, to: target) }
    }

    private func runRamp(from: Float, to target: Float) async {
        for step in 1 ... Self.rateRampSteps {
            try? await Task.sleep(for: Self.rateRamp / Self.rateRampSteps)
            guard !Task.isCancelled else { return }
            let rate = from + (target - from) * Float(step) / Float(Self.rateRampSteps)
            let volume = volume
            // Retired mid-ramp: the clock is another engine's now.
            guard onLayer({ $0.step(rate: rate, volume: volume) }) != nil else { return }
        }
    }
}
