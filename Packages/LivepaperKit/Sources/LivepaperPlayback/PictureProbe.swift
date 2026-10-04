import AVFoundation
import QuartzCore
import Synchronization

/// Polls the picture on screen from a queue of its own, and only while something is counting:
/// a watchdog window, or the metrics probe. Nothing polls otherwise. Its engine tells it of every
/// frame fed to the renderer, so that a window counts those over the same polls.
///
/// Its own queue, at a high priority, because the engine's queue waits on the reader and a late
/// poll reads as a late picture.
final class PictureProbe: Sendable {
    /// At 30 fps the gap limit is 50 ms and at 60 fps 25 ms: the spike polled every 4 ms.
    static let interval = DispatchTimeInterval.milliseconds(4)

    /// Its engine's gate: once the engine is retired the probe sees no picture.
    private let gate: RetirementGate<LayerAccess>
    private let queue = DispatchSerialQueue(label: "app.livepaper.playback.probe", qos: .userInteractive)
    private let state = Mutex(State())
    /// Frames the engine has fed the renderer, ever: a window takes the difference.
    private let fed = Atomic(0)

    private struct State {
        var timer: (any DispatchSourceTimer)?
        var windows: [Window] = []
        var gaps: PresentedGaps?
    }

    private struct Window {
        var counter: DisplayedPictureCounter
        let continuation: CheckedContinuation<PictureCount, Never>
    }

    init(gate: RetirementGate<LayerAccess>) {
        self.gate = gate
    }

    // A resumed timer lives until it is cancelled.
    deinit {
        state.withLock { $0.timer?.cancel() }
    }

    /// The new pictures shown over `window`, and the frames fed between the same polls, polled
    /// for that window and no longer.
    func count(over window: Duration, frameDuration: Double) async -> PictureCount {
        await withCheckedContinuation { continuation in
            let counter = DisplayedPictureCounter(from: CACurrentMediaTime(), window: window, frameDuration: frameDuration)
            state.withLock { state in
                state.windows.append(Window(counter: counter, continuation: continuation))
                startPolling(&state)
            }
        }
    }

    /// The engine put a frame on the renderer's queue. Called from the engine's queue, for every
    /// frame, so it takes no lock.
    func frameFed() {
        fed.wrappingAdd(1, ordering: .relaxed)
    }

    /// Starts measuring presented gaps afresh; nil stops.
    func measureGaps(frameDuration: Double?) {
        state.withLock { state in
            state.gaps = frameDuration.map(PresentedGaps.init(frameDuration:))
            if state.gaps != nil { startPolling(&state) }
        }
    }

    /// The clock stopped or the timeline started again.
    func interruptGaps() {
        let now = CACurrentMediaTime()
        state.withLock { $0.gaps?.interrupt(at: now) }
    }

    /// A pass's first frame is due on screen at this host time.
    func seam(dueAt time: Double) {
        state.withLock { $0.gaps?.seam(dueAt: time) }
    }

    var gaps: PresentedGaps? {
        state.withLock { $0.gaps }
    }

    private func startPolling(_ state: inout State) {
        guard state.timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: queue)
        timer.schedule(deadline: .now(), repeating: Self.interval, leeway: .milliseconds(1))
        timer.setEventHandler { [weak self] in self?.poll() }
        timer.resume()
        state.timer = timer
    }

    private func poll() {
        let picture = displayedPicture()
        let fedSoFar = fed.load(ordering: .relaxed)
        let now = CACurrentMediaTime()
        let finished = state.withLock { state in
            state.gaps?.observe(picture, at: now)
            var finished: [(CheckedContinuation<PictureCount, Never>, PictureCount)] = []
            var open: [Window] = []
            for var window in state.windows {
                window.counter.observe(picture, fed: fedSoFar, at: now)
                if window.counter.isOver(at: now) {
                    finished.append((window.continuation, window.counter.count))
                } else {
                    open.append(window)
                }
            }
            state.windows = open
            if state.windows.isEmpty, state.gaps == nil {
                state.timer?.cancel()
                state.timer = nil
            }
            return finished
        }
        for (continuation, count) in finished {
            continuation.resume(returning: count)
        }
    }

    /// The call hands back a new `CVPixelBuffer` every time, so the buffer says nothing; the
    /// `IOSurface` behind it stays the same while that picture is up.
    private func displayedPicture() -> PictureID? {
        guard let buffer = gate.pass({ $0.renderer.displayedPixelBuffer() }) ?? nil,
              let backing = CVPixelBufferGetIOSurface(buffer)?.takeUnretainedValue() else { return nil }
        return IOSurfaceGetID(backing)
    }
}
