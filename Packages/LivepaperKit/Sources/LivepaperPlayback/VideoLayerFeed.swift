import AVFoundation

/// One video layer as its engines see it: the layer's video renderer, the layer's synchroniser,
/// which clocks that renderer and, while the volume is up, the engine's audio, and the hardware
/// decoder the renderer holds.
///
/// Made once per layer, on the main actor where AVFoundation keeps the layer, and shared by the
/// engines that drive the layer in turn. The renderer stays on the one synchroniser for the
/// layer's life, so an engine that takes a layer over never has to wait for another to let go
/// of it.
///
/// `@unchecked Sendable` because AVFoundation does not mark the renderer or the synchroniser
/// Sendable, though both are made to be fed and clocked from a queue other than the layer's.
/// It holds because, once made here, nothing calls them except through an engine's
/// `RetirementGate`, one call at a time (the engine's feeding, its probe and its snapshot
/// alike), and a layer has one engine whose gate is open: an owner retires an engine, which
/// closes its gate and waits for a call under way, before it hands the layer to another.
/// `decoder` is Sendable on its own.
public struct VideoLayerFeed: @unchecked Sendable {
    let renderer: AVSampleBufferVideoRenderer
    let synchroniser: AVSampleBufferRenderSynchronizer
    let decoder = LayerDecoder()

    @MainActor
    public init(layer: AVSampleBufferDisplayLayer) {
        renderer = layer.sampleBufferRenderer
        synchroniser = AVSampleBufferRenderSynchronizer()
        // As the spike's bare timebase did: the first frame goes in with the clock stopped and
        // the clock starts when the engine says, not when the synchroniser thinks it has enough.
        synchroniser.delaysRateChangeUntilHasSufficientMediaData = false
        synchroniser.addRenderer(renderer)
    }
}

/// What one engine may touch on its layer, and only through its `RetirementGate`: the layer's
/// renderer, clock and decoder, and the engine's own audio renderer while that is on the clock.
struct LayerAccess {
    let renderer: AVSampleBufferVideoRenderer
    let synchroniser: AVSampleBufferRenderSynchronizer
    let decoder: LayerDecoder
    /// Made the first time the volume is up, and on the layer's synchroniser until let go.
    private(set) var audio: AVSampleBufferAudioRenderer?

    init(_ feed: VideoLayerFeed) {
        renderer = feed.renderer
        synchroniser = feed.synchroniser
        decoder = feed.decoder
    }

    /// Gives back the hardware decoder the renderer holds, if it holds one (`LayerDecoder`).
    /// Call once the renderer is flushed and the clock stopped: the picture it keeps stays where it is.
    func releaseDecoder() {
        guard let video = decoder.release(),
              let frame = releaseFrame(shapedLike: video, at: synchroniser.currentTime()) else { return }
        renderer.enqueue(frame)
    }

    /// The engine's audio renderer, made and put on the layer's clock the first time.
    mutating func audioRenderer() -> AVSampleBufferAudioRenderer {
        if let audio { return audio }
        let made = AVSampleBufferAudioRenderer()
        synchroniser.addRenderer(made)
        audio = made
        return made
    }

    /// Stops the audio and takes its renderer off the layer's clock.
    mutating func letAudioGo() {
        guard let audio else { return }
        audio.stopRequestingMediaData()
        audio.flush()
        synchroniser.removeRenderer(audio, at: .invalid, completionHandler: nil)
        self.audio = nil
    }
}
