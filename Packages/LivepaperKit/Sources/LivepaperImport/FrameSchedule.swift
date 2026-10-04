import Foundation

/// A constant frame rate, as the duration of one frame.
public struct FrameRate: Equatable, Sendable {
    public let duration: Int64
    public let timescale: Int32

    public init(duration: Int64, timescale: Int32) {
        self.duration = duration
        self.timescale = timescale
    }

    public var framesPerSecond: Double { Double(timescale) / Double(duration) }
    public var secondsPerFrame: Double { Double(duration) / Double(timescale) }

    /// The rate the optimised copy is written at when a source file is transcoded.
    ///
    /// A constant rate is kept to the tick. A variable one becomes the rate of
    /// its shortest frame, so that every frame is still shown, up to a ceiling
    /// that one stray short frame in a screen recording cannot push past.
    public static func forOptimisedCopy(of video: VideoProbe, ceiling: Double = 60) -> FrameRate {
        if case .constant(let rate) = video.timing, rate.duration > 0 { return rate }
        let fastest = video.minFrameDuration > 0 ? 1 / video.minFrameDuration : video.nominalFrameRate
        let framesPerSecond = fastest > 0 ? min(fastest, ceiling) : 30

        // The broadcast rates are not whole numbers and must not be rounded to one.
        let broadcast: [(Double, FrameRate)] = [
            (24000.0 / 1001, FrameRate(duration: 1001, timescale: 24000)),
            (30000.0 / 1001, FrameRate(duration: 1001, timescale: 30000)),
            (60000.0 / 1001, FrameRate(duration: 1001, timescale: 60000)),
        ]
        if let match = broadcast.first(where: { abs($0.0 - framesPerSecond) / $0.0 < 0.0005 }) { return match.1 }
        return FrameRate(duration: 100, timescale: Int32(max(1, framesPerSecond.rounded())) * 100)
    }

    /// Every nth frame, with n the smallest that brings the rate to the limit or under it.
    public func reduced(toAtMost limit: Double) -> FrameRate {
        let step = Int64(max(1, (framesPerSecond / limit).rounded(.up)))
        return FrameRate(duration: duration * step, timescale: timescale)
    }
}

/// Turns frames at any times into frames at a constant rate: slot `k` is at
/// `k` frame durations and shows the last source frame that starts before its
/// middle. A frame that fills no slot is left out, one that fills several is held.
///
/// It works one frame behind, because how long a frame is shown is only known
/// when the next one arrives.
public struct ConstantRateResampler: Sendable {
    public let rate: FrameRate
    public private(set) var framesWritten = 0
    private var origin: Double?

    public init(rate: FrameRate) {
        self.rate = rate
    }

    /// Takes the next source frame's time, in seconds, and answers how many
    /// slots the frame *before* it fills. Nil for the first frame, which has none before it.
    public mutating func next(pts: Double) -> Int? {
        guard let origin else {
            origin = pts
            return nil
        }
        return fill(upTo: pts - origin)
    }

    /// How many slots the last frame fills, given where the track's frames end.
    public mutating func finish(end: Double) -> Int {
        let count = fill(upTo: end - (origin ?? end))
        guard framesWritten == 0 else { return count }
        framesWritten = 1
        return 1
    }

    private mutating func fill(upTo time: Double) -> Int {
        let slot = max(framesWritten, Int((time / rate.secondsPerFrame).rounded(.toNearestOrAwayFromZero)))
        defer { framesWritten = slot }
        return slot - framesWritten
    }
}
