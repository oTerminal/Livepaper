// The retiming (one ever-increasing timeline, each pass continuing where the last one ended) is
// adapted from Phosphene's VideoRenderer.swift (MIT, (c) 2026 kageroumado,
// https://github.com/kageroumado/phosphene). See NOTICE at the repository root.

import CoreMedia

/// What the ledger needs to know about one buffer the reader vends.
struct VendedBuffer: Equatable, Sendable {
    var sampleCount: Int
    var hasDataBuffer: Bool
    /// In media time: before the edit list.
    var presentationTime: CMTime
    /// After the edit list: what the layer honours.
    var outputPresentationTime: CMTime
    /// Invalid when the stream has none.
    var decodeTime: CMTime
    /// Invalid when the reader does not know it.
    var duration: CMTime
}

/// Where one frame goes on the engine's timeline.
struct FrameStamp: Equatable, Sendable {
    var presentationTime: CMTime
    /// Invalid when the frame had none.
    var decodeTime: CMTime
    /// Added to every time of the buffer: the stamps above minus the vended media times.
    var shift: CMTime
    /// The first frame of a pass after the first: the loop seam.
    var opensSeam: Bool
    /// Every pass after the first starts at an IDR of the same stream, where the reader's
    /// `ResetDecoderBeforeDecoding` buys nothing but lands while the last pass is still decoding.
    var dropsDecoderReset: Bool
}

/// The engine's books for the gapless loop.
///
/// The layer sees one timeline that only ever increases: each frame is stamped with its output
/// (edit-list-adjusted) time plus the pass's offset, and the next pass starts at the end of the
/// last frame minus the file's first presentation time. Two things the spike paid for: the
/// reader brackets the frames with marker buffers, one of them stamped with the track's
/// duration, and they are not frames; and the reader leaves presentation times in media time
/// with the edit list as a separate output time, which the layer honours, so stamping the
/// first pass as vended would play it two frames early.
struct PassLedger: Sendable {
    let frameDuration: CMTime
    /// Added to the output times of the pass being stamped.
    private(set) var offset = CMTime.zero
    /// The latest end of any frame stamped: the maximum, not the last, since B-frames come out of order.
    private(set) var enqueuedUntil = CMTime.zero
    /// The output time of the file's first frame. Zero for a well-formed file.
    private(set) var firstPresentationTime: CMTime?
    /// Passes finished.
    private(set) var loops = 0
    private(set) var markersSkipped = 0
    /// From the latest frame of one pass to the earliest of the next, in frame durations. 1 is gapless.
    private(set) var largestSeamStep: Double?
    /// Between frames next to each other inside a pass, in frame durations.
    private(set) var largestInLoopStep: Double?

    /// Presentation times of the pass being stamped, in the order they came.
    private var passTimes: [CMTime] = []
    private var lastPassLatest: CMTime?

    init(frameDuration: CMTime) {
        self.frameDuration = frameDuration
    }

    /// The stamp for `buffer`, or nil when it is a marker rather than a frame. A frame is a
    /// buffer with at least one sample and the data behind it.
    mutating func stamp(_ buffer: VendedBuffer) -> FrameStamp? {
        let output = buffer.outputPresentationTime
        guard buffer.sampleCount > 0, buffer.hasDataBuffer, output.isNumeric else {
            markersSkipped += 1
            return nil
        }
        if firstPresentationTime == nil { firstPresentationTime = output }

        let presentation = output + offset
        let shift = presentation - (buffer.presentationTime.isNumeric ? buffer.presentationTime : output)
        let decode = buffer.decodeTime.isNumeric ? buffer.decodeTime + shift : .invalid
        let duration = buffer.duration.isNumeric && buffer.duration > .zero ? buffer.duration : frameDuration
        enqueuedUntil = max(enqueuedUntil, presentation + duration)

        let opensSeam = passTimes.isEmpty && loops > 0
        passTimes.append(presentation)
        return FrameStamp(
            presentationTime: presentation,
            decodeTime: decode,
            shift: shift,
            opensSeam: opensSeam,
            dropsDecoderReset: loops > 0
        )
    }

    /// Ends the pass: the next one continues where this one's last frame ends. A pass that
    /// stamped nothing changes nothing.
    mutating func finishPass() {
        guard !passTimes.isEmpty else { return }
        offset = enqueuedUntil - (firstPresentationTime ?? .zero)

        // Steps are taken in exact time and only then divided, so that an even file reads exactly 1.
        let times = passTimes.sorted()
        let frame = frameDuration.seconds
        if frame > 0 {
            for (earlier, later) in zip(times, times.dropFirst()) {
                largestInLoopStep = max(largestInLoopStep ?? 0, (later - earlier).seconds / frame)
            }
            if let lastPassLatest, let earliest = times.first {
                largestSeamStep = max(largestSeamStep ?? 0, (earliest - lastPassLatest).seconds / frame)
            }
        }
        lastPassLatest = times.last
        passTimes.removeAll(keepingCapacity: true)
        loops += 1
    }
}
