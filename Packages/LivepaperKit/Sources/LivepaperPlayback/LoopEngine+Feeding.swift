// Feeding the layer pass after pass on one timeline. Adapted from Phosphene's VideoRenderer.swift
// (MIT, (c) 2026 kageroumado, https://github.com/kageroumado/phosphene) by way of the spike's
// LoopEngine, with the spike's fixes. See NOTICE at the repository root.

import AVFoundation
import QuartzCore

/// Trouble on the layer, which the engine answers by starting again from a fresh reader.
enum EngineTrouble {
    case rendererFailed((any Error)?)
    case rendererAskedForFlush
    case readerFailed((any Error)?)
    case audioFailed((any Error)?)
    case passWithoutFrames
}

extension LayerAccess {
    /// What the video renderer's state says is wrong, if anything.
    var rendererTrouble: EngineTrouble? {
        if renderer.status == .failed { return .rendererFailed(renderer.error) }
        if renderer.requiresFlushToResumeDecoding { return .rendererAskedForFlush }
        return nil
    }

    var audioTrouble: EngineTrouble? {
        guard let audio, audio.status == .failed else { return nil }
        return .audioFailed(audio.error)
    }

    /// A start's first frame, pushed to the render server at once: the layer lives in a remote
    /// context. The renderer makes a hardware decoder for it.
    func enqueueFirst(_ frame: CMSampleBuffer) {
        decoder.fed(frame.formatDescription)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        renderer.enqueue(frame)
        CATransaction.commit()
        CATransaction.flush()
    }

    /// Drops what is queued on the video and the audio renderers, keeping the picture on screen.
    func flushQueued() {
        renderer.flush()
        audio?.flush()
    }

    /// One step of a rate ramp; the sound follows the picture down and up, so that it does not click.
    func step(rate: Float, volume: Double) {
        synchroniser.rate = rate
        audio?.volume = Float(volume) * rate
    }
}

extension LoopEngine {
    var wantsAudio: Bool {
        volume > 0 && !audioBroken && media?.audioTrack != nil
    }

    /// Runs `body` on the engine's queue after what is queued there already: the way out of a
    /// renderer's callback, which may not re-enter itself.
    nonisolated func later(_ body: @escaping @Sendable (isolated LoopEngine) -> Void) {
        queue.async { [weak self] in self?.assumeIsolated(body) }
    }

    // MARK: Video

    /// The first frame goes in with the clock stopped and is shown as soon as it is decoded, so
    /// that it cannot be judged late; its presentation time comes back, nil when the pass had
    /// no frame or the engine was retired meanwhile. The first buffer a reader vends is a
    /// marker: skip to a frame.
    func enqueueFirstFrame(from pass: ReaderPass) -> CMTime? {
        while let buffer = pass.video.copyNextSampleBuffer() {
            guard let frame = stamped(buffer) else { continue }
            frame.displayImmediately()
            guard onLayer({ $0.enqueueFirst(frame) }) != nil else { return nil }
            probe.frameFed()
            return frame.presentationTimeStamp
        }
        return nil
    }

    func feedVideo(_ run: Int) {
        onLayer { access in
            access.renderer.requestMediaDataWhenReady(on: queue) { [weak self] in
                self?.assumeIsolated { $0.pumpVideo(run) }
            }
        }
    }

    private func pumpVideo(_ run: Int) {
        // A call for an earlier start may have been queued before that start was stopped: what
        // is registered now is the current start's, and stopping it here would stall it.
        guard run == generation, let found = onLayer({ $0.rendererTrouble }) else { return }
        if let trouble = found {
            troubled(run, trouble)
            return
        }
        while onLayer({ $0.renderer.isReadyForMoreMediaData }) == true {
            guard let pass = videoPass else { return }
            // Blocks until the reader has the next buffer; the engine may be retired meanwhile,
            // and then the gate turns away everything after the read.
            guard let buffer = pass.video.copyNextSampleBuffer() else {
                onLayer { $0.renderer.stopRequestingMediaData() }
                if pass.reader.status == .failed {
                    // Nil also means the reader broke, which is not the end of a pass.
                    troubled(run, .readerFailed(pass.reader.error))
                } else {
                    later { $0.videoPassEnded(run) }
                }
                return
            }
            guard let frame = stamped(buffer) else { continue }
            guard onLayer({ $0.renderer.enqueue(frame) }) != nil else { return }
            probe.frameFed()
        }
    }

    /// The buffer as the layer is to see it, or nil for a marker.
    private func stamped(_ buffer: CMSampleBuffer) -> CMSampleBuffer? {
        guard let stamp = ledger.stamp(buffer.vended) else { return nil }
        if stamp.opensSeam { noteSeam(at: stamp.presentationTime) }
        guard let frame = buffer.shifted(by: stamp.shift) else { return nil }
        if stamp.dropsDecoderReset { frame.dropDecoderReset() }
        return frame
    }

    private func noteSeam(at time: CMTime) {
        guard case let (now, rate)? = onLayer({ ($0.synchroniser.currentTime(), Double($0.synchroniser.rate)) }) else { return }
        let lead = (time - now).seconds
        tally.smallestSeamLead = min(tally.smallestSeamLead ?? lead, lead)
        if metricsSubject != nil, rate > 0 {
            probe.seam(dueAt: CACurrentMediaTime() + lead / rate)
        }
    }

    /// The renderer's own word, heard by notification: a renderer that failed or needs a flush
    /// stops asking for data, so the pull callback may never see it.
    func rendererSignalled(_ signal: RendererSignal) {
        guard !isRetired, lifecycle == .running, videoPass != nil else { return }
        let trouble: EngineTrouble? = switch signal {
        case .failedToDecode(let error): .rendererFailed(error)
        case .requiresFlushChanged: onLayer { $0.renderer.requiresFlushToResumeDecoding } == true ? .rendererAskedForFlush : nil
        }
        guard let trouble else { return }
        troubled(generation, trouble)
    }

    func observeRenderer() {
        guard rendererObservation == nil else { return }
        rendererObservation = onLayer { access in
            RendererObservation(access.renderer) { [weak self] signal in
                self?.later { $0.rendererSignalled(signal) }
            }
        }
    }

    /// Trouble on the layer: start again from a fresh reader, since the one in hand is mid-GOP,
    /// once however many ways it is reported. A file that keeps failing is left for the watchdog.
    private func troubled(_ run: Int, _ trouble: EngineTrouble) {
        guard run == generation, !isRetired else { return }
        onLayer { $0.renderer.stopRequestingMediaData() }
        switch troubles.trouble() {
        case .ignore:
            return
        case .restart:
            record(trouble)
            Task { await self.restart() }
        case .giveUp:
            record(trouble)
            logger.error("\(EngineLog.gaveUp(self.video?.url, restarts: TroubleResponse.limit), privacy: .public)")
            haltFeeding()
        }
    }

    private func record(_ trouble: EngineTrouble) {
        let url = video?.url
        switch trouble {
        case .rendererFailed(let error):
            tally.failures += 1
            logger.error("\(EngineLog.rendererFailed(url, error), privacy: .public)")
        case .rendererAskedForFlush:
            // The decoder needs a sync frame after a flush, and the reader is somewhere in the
            // middle of a GOP: start the file again rather than feed it P-frames.
            tally.flushes += 1
            logger.notice("\(EngineLog.rendererAskedForFlush(url), privacy: .public)")
        case .readerFailed(let error):
            tally.failures += 1
            logger.error("\(EngineLog.readerFailed(url, error), privacy: .public)")
        case .audioFailed(let error):
            tally.failures += 1
            logger.error("\(EngineLog.audioFailed(url, error), privacy: .public)")
        case .passWithoutFrames:
            tally.failures += 1
            logger.error("\(EngineLog.passWithoutFrames(url), privacy: .public)")
        }
    }

    private func videoPassEnded(_ run: Int) {
        guard run == generation, !isRetired, let finished = videoPass, let media else { return }
        let loopsBefore = ledger.loops
        ledger.finishPass()
        guard ledger.loops > loopsBefore else {
            // A pass with no frames would loop for ever and show nothing.
            troubled(run, .passWithoutFrames)
            return
        }
        troubles.loopCompleted()
        loopCompleted()

        let next: ReaderPass
        if let opened = nextPass {
            next = opened
        } else {
            tally.nextReaderMisses += 1
            do {
                next = try ReaderPass(reading: media, withAudio: wantsAudio)
            } catch {
                troubled(run, .readerFailed(error))
                return
            }
        }
        nextPass = nil
        next.offset = ledger.offset
        videoPass = next

        if audioPass === finished, !audioWaitsForVideo {
            // The audio is still reading this pass, and moves on when it reaches its end.
        } else {
            finished.cancel()
            if audioPass === finished || audioPass == nil {
                audioWaitsForVideo = false
                moveAudio(to: next, run)
            }
        }
        feedVideo(run)
        openNextPassLater(run)
    }

    // MARK: The next reader

    func openNextPassLater(_ run: Int) {
        later { $0.openNextPass(run) }
    }

    private func openNextPass(_ run: Int) {
        guard run == generation, !isRetired, nextPass == nil, let media else { return }
        // A miss here is tried again at the seam and counted there.
        nextPass = try? ReaderPass(reading: media, withAudio: wantsAudio)
    }

    /// The volume went on or off: the next pass's reader is opened again, with or without the audio track.
    func reopenNextPass(_ run: Int) async {
        if volume > 0, !audioBroken {
            await loadAudioTrack()
        }
        guard run == generation else { return }
        nextPass?.cancel()
        nextPass = nil
        openNextPassLater(run)
    }

    func loadAudioTrack() async {
        guard let asset = media?.asset, media?.audioTrackLoaded == false else { return }
        let track = try? await asset.loadTracks(withMediaType: .audio).first
        guard media?.asset === asset else { return }
        media?.audioTrack = track
        media?.audioTrackLoaded = true
    }

    // MARK: Audio

    /// The audio reads `pass` from its start, stamped with that pass's offset, into an audio
    /// renderer on the layer's synchroniser; a pass without the audio track ends the audio.
    func moveAudio(to pass: ReaderPass, _ run: Int) {
        guard pass.audio != nil else {
            dropAudio()
            return
        }
        audioPass = pass
        let level = Float(volume) * (isPaused ? 0 : 1)
        onLayer { access in
            let audio = access.audioRenderer()
            audio.volume = level
            audio.requestMediaDataWhenReady(on: queue) { [weak self] in
                self?.assumeIsolated { $0.pumpAudio(run) }
            }
        }
    }

    private func pumpAudio(_ run: Int) {
        // As for the video: a call for an earlier start leaves the current registration alone.
        guard run == generation, let found = onLayer({ $0.audioTrouble }) else { return }
        if let trouble = found {
            // An audio output left unread can hold the video up, so the video starts again without it.
            audioBroken = true
            dropAudio()
            troubled(run, trouble)
            return
        }
        while onLayer({ $0.audio?.isReadyForMoreMediaData }) == true {
            guard let pass = audioPass, let output = pass.audio else {
                onLayer { $0.audio?.stopRequestingMediaData() }
                return
            }
            guard let buffer = output.copyNextSampleBuffer() else {
                onLayer { $0.audio?.stopRequestingMediaData() }
                later { $0.audioPassEnded(run) }
                return
            }
            guard buffer.numSamples > 0, buffer.dataBuffer != nil,
                  let sample = buffer.shifted(by: pass.offset + buffer.editShift) else { continue }
            guard onLayer({ $0.audio?.enqueue(sample) }) != nil else { return }
        }
    }

    private func audioPassEnded(_ run: Int) {
        guard run == generation, !isRetired, let finished = audioPass else { return }
        guard let newer = videoPass, newer !== finished else {
            // The video is still in this pass; its seam brings the audio along.
            audioWaitsForVideo = true
            return
        }
        finished.cancel()
        moveAudio(to: newer, run)
    }

    func dropAudio() {
        audioPass = nil
        audioWaitsForVideo = false
        onLayer { $0.letAudioGo() }
    }

    // MARK: Metrics

    private func loopCompleted() {
        guard let subject = metricsSubject, (tally.loops + ledger.loops) % Self.metricsInterval == 0 else { return }
        let metrics = metrics()
        let logger = logger
        onLayer { access in
            access.renderer.loadVideoPerformanceMetrics { performance in
                var metrics = metrics
                metrics.droppedFrames = performance?.numberOfDroppedFrames
                metrics.totalFrames = performance?.totalNumberOfFrames
                logger.notice("\(metrics.logLine(for: subject), privacy: .public)")
            }
        }
    }
}
