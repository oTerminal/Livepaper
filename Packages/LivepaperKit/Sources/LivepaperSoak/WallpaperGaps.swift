import Foundation

/// What the metrics lines say of each wallpaper: its largest presented gap and
/// whether that was at a seam, and its gaps over `limit` split at-seam and
/// mid-pass. A gap at a seam is the engine's own; one mid-pass at 60 fps comes
/// from load.
public struct WallpaperGaps: Equatable, Sendable {
    /// `PresentedGaps.limit` in the engine (LivepaperPlayback): 1.5 frame durations.
    public static let limit = 1.5

    public struct Wallpaper: Equatable, Sendable {
        /// The optimised copy's folder: for a library video, the wallpaper's ID.
        public var folder: String
        public var loops: Int
        public var largest: Double?
        public var isLargestAtSeam: Bool
        public var overLimitAtSeams: Int
        public var overLimitMidPass: Int
        /// The engine's own stamps: its largest seam step (1 is gapless) and its smallest lead at a seam.
        /// A late picture with a step of 1 and a lead to spare was queued on time and shown late.
        public var largestSeamStep: Double?
        public var smallestSeamLead: Double?

        public init(
            folder: String, loops: Int, largest: Double?, isLargestAtSeam: Bool, overLimitAtSeams: Int, overLimitMidPass: Int,
            largestSeamStep: Double? = nil, smallestSeamLead: Double? = nil
        ) {
            self.folder = folder
            self.loops = loops
            self.largest = largest
            self.isLargestAtSeam = isLargestAtSeam
            self.overLimitAtSeams = overLimitAtSeams
            self.overLimitMidPass = overLimitMidPass
            self.largestSeamStep = largestSeamStep
            self.smallestSeamLead = smallestSeamLead
        }
    }

    public private(set) var wallpapers: [Wallpaper] = []

    /// An engine's numbers run from its start on a video, so each run's last line
    /// holds its counts; a line with no more loops than the one before is a new run.
    public init(_ lines: [MetricsLine]) {
        var latest: [String: MetricsLine] = [:]
        var finals: [MetricsLine] = []
        for line in lines {
            let engine = "\(line.surface ?? "preview") \(line.folder)"
            if let last = latest[engine], line.loops <= last.loops { finals.append(last) }
            latest[engine] = line
        }
        finals += latest.values

        var byFolder: [String: Wallpaper] = [:]
        for line in finals {
            var wallpaper = byFolder[line.folder]
                ?? Wallpaper(folder: line.folder, loops: 0, largest: nil, isLargestAtSeam: false, overLimitAtSeams: 0, overLimitMidPass: 0)
            wallpaper.loops += line.loops
            wallpaper.overLimitAtSeams += line.gapsOverLimitAtSeams
            wallpaper.overLimitMidPass += line.gapsOverLimitElsewhere
            byFolder[line.folder] = wallpaper
        }
        // The largest gap and step, and the smallest lead, are the extremes any line saw, whichever run it was in.
        for line in lines {
            guard var wallpaper = byFolder[line.folder] else { continue }
            if let step = line.largestSeamStep { wallpaper.largestSeamStep = max(step, wallpaper.largestSeamStep ?? step) }
            if let lead = line.smallestSeamLead { wallpaper.smallestSeamLead = min(lead, wallpaper.smallestSeamLead ?? lead) }
            byFolder[line.folder] = wallpaper
        }
        for line in lines {
            guard let gap = line.largestPresentedGap, gap > byFolder[line.folder]?.largest ?? -1 else { continue }
            byFolder[line.folder]?.largest = gap
            byFolder[line.folder]?.isLargestAtSeam = line.largestPresentedGapAtSeam == gap
        }
        wallpapers = byFolder.values.sorted { $0.folder < $1.folder }
    }
}
