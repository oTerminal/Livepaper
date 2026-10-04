import Foundation

/// What the spike's `summary` logged, for one engine: the numbers the checks and the soak
/// read off the log while the probe is on. Gaps and steps are in frame durations.
public struct PlaybackMetrics: Equatable, Sendable {
    /// Whose numbers these are, as the log line names it.
    public enum Subject: Equatable, Sendable, CustomStringConvertible {
        case surface(SurfaceID)
        case preview

        public var description: String {
            switch self {
            case .surface(let id): "surface \(id)"
            case .preview: "preview"
            }
        }
    }

    /// The optimised copy's folder and file name, which for the library is the wallpaper's ID.
    public var video: String
    public var loops = 0
    /// Seams that fell inside an interval the probe measured.
    public var seamsWatched = 0
    /// From the latest frame of a pass to the earliest of the next, by the engine's own stamps. 1 is gapless.
    public var largestSeamStep: Double?
    public var largestInLoopStep: Double?
    /// How long a picture stayed on screen, by the displayed-picture probe.
    public var largestPresentedGap: Double?
    public var largestPresentedGapAtSeam: Double?
    /// Pictures up for longer than `PresentedGaps.limit` frame durations.
    public var gapsOverLimitAtSeams = 0
    public var gapsOverLimitElsewhere = 0
    /// From `AVVideoPerformanceMetrics`, which did not see the seam defect: a second opinion only.
    public var droppedFrames: Int?
    public var totalFrames: Int?
    /// Seconds between the timebase and the first frame of a pass as it was enqueued. Negative is a layer that ran dry.
    public var smallestSeamLead: Double?
    public var flushes = 0
    public var failures = 0
    public var markerBuffersSkipped = 0
    /// Seams at which the reader opened ahead was not ready and one was opened there and then.
    public var nextReaderMisses = 0

    public init(
        video: String,
        loops: Int = 0,
        seamsWatched: Int = 0,
        largestSeamStep: Double? = nil,
        largestInLoopStep: Double? = nil,
        largestPresentedGap: Double? = nil,
        largestPresentedGapAtSeam: Double? = nil,
        gapsOverLimitAtSeams: Int = 0,
        gapsOverLimitElsewhere: Int = 0,
        droppedFrames: Int? = nil,
        totalFrames: Int? = nil,
        smallestSeamLead: Double? = nil,
        flushes: Int = 0,
        failures: Int = 0,
        markerBuffersSkipped: Int = 0,
        nextReaderMisses: Int = 0
    ) {
        self.video = video
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
        self.markerBuffersSkipped = markerBuffersSkipped
        self.nextReaderMisses = nextReaderMisses
    }

    /// The metrics line, logged every `LoopEngine.metricsInterval` loops while the probe is on.
    /// Its wording is fixed: the soak's parser and the release checklist read it.
    public func logLine(for subject: Subject) -> String {
        "playback metrics for \(subject) on \(video): loops \(loops), seams watched \(seamsWatched), "
            + "seam step \(Self.format(largestSeamStep)), in-loop step \(Self.format(largestInLoopStep)), "
            + "presented gap \(Self.format(largestPresentedGap)), at a seam \(Self.format(largestPresentedGapAtSeam)), "
            + "gaps over 1.5 at seams \(gapsOverLimitAtSeams), elsewhere \(gapsOverLimitElsewhere), "
            + "renderer dropped \(Self.format(droppedFrames)) of \(Self.format(totalFrames)), "
            + "seam lead \(Self.format(smallestSeamLead)) s, flushes \(flushes), failures \(failures), "
            + "markers skipped \(markerBuffersSkipped), next-reader misses \(nextReaderMisses)"
    }

    private static func format(_ value: Double?) -> String {
        value.map { String(format: "%.2f", $0) } ?? "none"
    }

    private static func format(_ value: Int?) -> String {
        value.map(String.init) ?? "none"
    }
}
