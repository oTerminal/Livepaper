import Foundation

/// What the engine's reader vends for a video track, with the marker buffers
/// that carry no media already left out. Times are ticks of the track's timescale.
public struct TrackReading: Equatable, Sendable {
    public struct Frame: Equatable, Sendable {
        public var pts: Int64
        public var duration: Int64
        /// A full sync sample: it decodes with nothing before it.
        public var isSync: Bool

        public init(pts: Int64, duration: Int64, isSync: Bool) {
            self.pts = pts
            self.duration = duration
            self.isSync = isSync
        }
    }

    public var timescale: Int32
    /// In the order the reader vends them, which is decode order.
    public var frames: [Frame]
    public var trackDuration: Int64
    /// Whether the track's edits do anything but play its media from zero, as it is.
    public var hasEditList: Bool

    public init(timescale: Int32, frames: [Frame], trackDuration: Int64, hasEditList: Bool) {
        self.timescale = timescale
        self.frames = frames
        self.trackDuration = trackDuration
        self.hasEditList = hasEditList
    }
}

public enum LoopSeamFailure: Equatable, Sendable {
    case noFrames
    case firstFrameNotAtZero
    case firstFrameNotSync
    case unevenFrames
    case trackDurationNotEndOfLastFrame
    case editList
    case seamStepNotOneFrame
    case framesBeforeFirstSync
}

/// The loop-seam validator's findings: the numbers, not just pass or fail.
public struct LoopSeamReport: Equatable, Sendable, CustomStringConvertible {
    public var timescale: Int32
    public var frameCount: Int
    /// Of the first frame in presentation order.
    public var firstPTS: Int64?
    public var frameDuration: Int64?
    /// The furthest any step between two frames is from the frame duration.
    public var largestStepError: Int64
    public var endOfLastFrame: Int64?
    public var trackDuration: Int64
    /// `first PTS + loop length − last PTS`: what the display sees between the last frame and the first.
    public var seamStep: Int64?
    /// Frames whose decoding needs something from before the first sync sample.
    public var framesBeforeFirstSync: Int
    public var hasEditList: Bool
    public var failures: [LoopSeamFailure]

    public var passes: Bool { failures.isEmpty }

    public var description: String {
        func ticks(_ value: Int64?) -> String { value.map(String.init) ?? "none" }
        return [
            passes ? "loop seam clean" : "loop seam not clean \(failures)",
            "\(frameCount) frames at 1/\(timescale)",
            "first PTS \(ticks(firstPTS))",
            "frame duration \(ticks(frameDuration))",
            "largest step error \(largestStepError)",
            "end of last frame \(ticks(endOfLastFrame))",
            "track duration \(trackDuration)",
            "seam step \(ticks(seamStep))",
            "frames before first sync \(framesBeforeFirstSync)",
            "edit list \(hasEditList)",
        ].joined(separator: ", ")
    }
}

/// Whether a track loops without a gap when the engine plays it.
///
/// The engine continues the next pass at `end of last frame − PTS of first
/// frame`, so a first frame off zero, uneven frames or a track longer than its
/// frames all show up as a stall at the seam.
public func judgeLoopSeam(_ reading: TrackReading) -> LoopSeamReport {
    // One tick of the track's timescale, for the steps between frames and so for the seam step
    // that follows from them. The track's duration has to be exact.
    let tolerance: Int64 = 1
    let shown = reading.frames.sorted { $0.pts < $1.pts }
    var report = LoopSeamReport(
        timescale: reading.timescale, frameCount: shown.count, largestStepError: 0, trackDuration: reading.trackDuration,
        framesBeforeFirstSync: 0, hasEditList: reading.hasEditList, failures: []
    )
    guard let first = shown.first, let last = shown.last else {
        report.failures = [.noFrames]
        return report
    }

    let frameDuration = first.duration
    let steps = zip(shown, shown.dropFirst()).map { $1.pts - $0.pts }
    report.firstPTS = first.pts
    report.frameDuration = frameDuration
    report.largestStepError = steps.map { abs($0 - frameDuration) }.max() ?? 0
    report.endOfLastFrame = last.pts + last.duration
    report.seamStep = first.pts + reading.trackDuration - last.pts
    report.framesBeforeFirstSync = framesBeforeFirstSync(reading.frames)

    if first.pts != 0 { report.failures.append(.firstFrameNotAtZero) }
    if !first.isSync { report.failures.append(.firstFrameNotSync) }
    if report.largestStepError > tolerance { report.failures.append(.unevenFrames) }
    if last.pts + last.duration != reading.trackDuration { report.failures.append(.trackDurationNotEndOfLastFrame) }
    if reading.hasEditList { report.failures.append(.editList) }
    if abs(first.pts + reading.trackDuration - last.pts - frameDuration) > tolerance { report.failures.append(.seamStepNotOneFrame) }
    if report.framesBeforeFirstSync > 0 { report.failures.append(.framesBeforeFirstSync) }
    return report
}

/// Frames decoded before the first sync sample, and leading pictures: decoded
/// after it, shown before it, and predicted from a GOP that is not there.
private func framesBeforeFirstSync(_ decodeOrder: [TrackReading.Frame]) -> Int {
    guard let index = decodeOrder.firstIndex(where: \.isSync) else { return decodeOrder.count }
    let sync = decodeOrder[index]
    return index + decodeOrder[index...].count { $0.pts < sync.pts }
}
