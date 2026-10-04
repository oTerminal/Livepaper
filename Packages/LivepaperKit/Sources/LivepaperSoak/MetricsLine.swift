import Foundation

/// The engine's metrics line (`PlaybackMetrics.logLine(for:)`), logged every 20
/// loops while the probe is on. Its numbers run from the engine's start on that
/// video. Gaps and steps are in frame durations.
public struct MetricsLine: Equatable, Sendable {
    /// The surface's ID, or nil for the preview's.
    public var surface: String?
    /// The optimised copy's folder, which for a library video is the wallpaper's ID, and its file.
    public var folder: String
    public var file: String
    public var loops: Int
    public var seamsWatched: Int
    public var largestSeamStep: Double?
    public var largestInLoopStep: Double?
    public var largestPresentedGap: Double?
    public var largestPresentedGapAtSeam: Double?
    public var gapsOverLimitAtSeams: Int
    public var gapsOverLimitElsewhere: Int
    public var droppedFrames: Int?
    public var totalFrames: Int?
    public var smallestSeamLead: Double?
    public var flushes: Int
    public var failures: Int
    public var markersSkipped: Int
    public var nextReaderMisses: Int

    public init(
        surface: String?, folder: String, file: String, loops: Int, seamsWatched: Int,
        largestSeamStep: Double? = nil, largestInLoopStep: Double? = nil,
        largestPresentedGap: Double? = nil, largestPresentedGapAtSeam: Double? = nil,
        gapsOverLimitAtSeams: Int = 0, gapsOverLimitElsewhere: Int = 0,
        droppedFrames: Int? = nil, totalFrames: Int? = nil, smallestSeamLead: Double? = nil,
        flushes: Int = 0, failures: Int = 0, markersSkipped: Int = 0, nextReaderMisses: Int = 0
    ) {
        self.surface = surface
        self.folder = folder
        self.file = file
        self.loops = loops
        self.seamsWatched = seamsWatched
        self.largestSeamStep = largestSeamStep
        self.largestInLoopStep = largestInLoopStep
        self.largestPresentedGap = largestPresentedGap
        self.largestPresentedGapAtSeam = largestPresentedGapAtSeam
        self.gapsOverLimitAtSeams = gapsOverLimitAtSeams
        self.gapsOverLimitElsewhere = gapsOverLimitElsewhere
        self.droppedFrames = droppedFrames
        self.totalFrames = totalFrames
        self.smallestSeamLead = smallestSeamLead
        self.flushes = flushes
        self.failures = failures
        self.markersSkipped = markersSkipped
        self.nextReaderMisses = nextReaderMisses
    }

    /// `playback metrics for <subject> on <folder>/<file>: loops <n>, …, next-reader misses <n>`,
    /// every field present and in its order, or nil.
    init?(logged message: Substring) {
        let head = message.dropFirst("playback metrics for ".count)
        guard let on = head.range(of: " on "), let colon = head.range(of: ": ", range: on.upperBound..<head.endIndex) else { return nil }
        let subject = head[..<on.lowerBound]
        if subject == "preview" {
            surface = nil
        } else if subject.hasPrefix("surface ") {
            surface = String(subject.dropFirst("surface ".count))
        } else {
            return nil
        }
        let video = head[on.upperBound..<colon.lowerBound]
        let slash = video.lastIndex(of: "/")
        folder = String(slash.map { video[..<$0] } ?? video)
        file = slash.map { String(video[video.index(after: $0)...]) } ?? ""

        var reader = PairReader(head[colon.upperBound...])
        guard let loops = reader.int("loops"),
              let seamsWatched = reader.int("seams watched"),
              let seamStep = reader.number("seam step"),
              let inLoopStep = reader.number("in-loop step"),
              let presentedGap = reader.number("presented gap"),
              let atSeam = reader.number("at a seam"),
              let overAtSeams = reader.int("gaps over 1.5 at seams"),
              let overElsewhere = reader.int("elsewhere"),
              let dropped = reader.pair("renderer dropped", separator: " of "),
              let seamLead = reader.number("seam lead", unit: " s"),
              let flushes = reader.int("flushes"),
              let failures = reader.int("failures"),
              let markersSkipped = reader.int("markers skipped"),
              let nextReaderMisses = reader.int("next-reader misses"),
              reader.isAtEnd else { return nil }
        self.loops = loops
        self.seamsWatched = seamsWatched
        largestSeamStep = seamStep.value
        largestInLoopStep = inLoopStep.value
        largestPresentedGap = presentedGap.value
        largestPresentedGapAtSeam = atSeam.value
        gapsOverLimitAtSeams = overAtSeams
        gapsOverLimitElsewhere = overElsewhere
        droppedFrames = dropped.0.value.map { Int($0) }
        totalFrames = dropped.1.value.map { Int($0) }
        smallestSeamLead = seamLead.value
        self.flushes = flushes
        self.failures = failures
        self.markersSkipped = markersSkipped
        self.nextReaderMisses = nextReaderMisses
    }
}

/// The metrics line's `name value` pairs, read in order.
private struct PairReader {
    /// A number, or `none`.
    struct Number {
        var value: Double?
    }

    private var pairs: ArraySlice<Substring>

    init(_ text: Substring) {
        pairs = text.split(separator: ", ", omittingEmptySubsequences: false)[...]
    }

    var isAtEnd: Bool { pairs.isEmpty }

    mutating func int(_ name: String) -> Int? {
        take(name).flatMap { Int($0) }
    }

    mutating func number(_ name: String, unit: String = "") -> Number? {
        guard let text = take(name), text.hasSuffix(unit) else { return nil }
        return Self.number(text.dropLast(unit.count))
    }

    mutating func pair(_ name: String, separator: String) -> (Number, Number)? {
        guard let text = take(name), let middle = text.range(of: separator),
              let first = Self.number(text[..<middle.lowerBound]),
              let second = Self.number(text[middle.upperBound...]) else { return nil }
        return (first, second)
    }

    private mutating func take(_ name: String) -> Substring? {
        guard let pair = pairs.first, pair.hasPrefix(name + " ") else { return nil }
        pairs = pairs.dropFirst()
        return pair.dropFirst(name.count + 1)
    }

    private static func number(_ text: Substring) -> Number? {
        if text == "none" { return Number(value: nil) }
        return Double(text).map { Number(value: $0) }
    }
}
