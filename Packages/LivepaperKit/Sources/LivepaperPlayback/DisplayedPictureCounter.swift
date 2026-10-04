// Progress is judged by the pictures the layer really displayed:
// not by the timebase, and not by AVVideoPerformanceMetrics, since neither saw
// the seam defect. `displayedPixelBuffer()` hands back a new CVPixelBuffer every time, so a
// picture is told apart by the IOSurface behind it, which stays the same while it is up.

/// A picture on screen, as the ID of the `IOSurface` behind it: the same for as long as that
/// picture is up.
typealias PictureID = UInt32

/// Counts the new pictures a surface showed over one window, for the watchdog, and the frames
/// its engine fed the renderer over the same polls: a surface the window server does not
/// composite shows nothing new while it is fed as usual.
struct DisplayedPictureCounter: Equatable, Sendable {
    /// Host time, in seconds.
    let start: Double
    let end: Double
    let frameDuration: Double
    private var last: PictureID?
    private var changes = 0
    /// The engine's running total of frames fed, at the window's first poll and at its latest.
    private var fedAtFirst: Int?
    private var fedAtLatest: Int?

    init(from start: Double, window: Duration, frameDuration: Double) {
        self.start = start
        self.end = start + window / .seconds(1)
        self.frameDuration = frameDuration
    }

    /// One poll: the picture on screen at `time`, nil when there was none, and the frames the
    /// engine had fed the renderer by then. The first picture seen was already up, so it is not
    /// a new one.
    mutating func observe(_ picture: PictureID?, fed: Int, at time: Double) {
        guard time >= start, time < end else { return }
        if fedAtFirst == nil { fedAtFirst = fed }
        fedAtLatest = fed
        guard let picture else { return }
        if let last, picture != last { changes += 1 }
        last = picture
    }

    func isOver(at time: Double) -> Bool {
        time >= end
    }

    /// What `judgeProgress` takes: the new pictures, and one per frame of the window. With them
    /// the frames fed between the same two polls.
    var count: PictureCount {
        let expected = frameDuration > 0 ? Int(((end - start) / frameDuration).rounded()) : 0
        let fed = (fedAtLatest ?? 0) - (fedAtFirst ?? 0)
        return PictureCount(displayed: changes, expected: expected, fed: fed)
    }
}

/// The spike's presented-gap measure, for the playback metrics: how long each picture stayed
/// up, in frame durations, told apart at the loop seams and elsewhere.
struct PresentedGaps: Equatable, Sendable {
    /// A picture up for longer than this many frame durations is a gap.
    static let limit = 1.5
    /// After a start or a pause the decoder is warming up and the clock may be ramping: the
    /// spike's probe waited this long before it measured.
    static let settling = 0.5

    let frameDuration: Double
    /// Intervals between two changes of picture that were measured.
    private(set) var intervals = 0
    private(set) var largest: Double?
    private(set) var largestAtSeam: Double?
    private(set) var overLimitAtSeams = 0
    private(set) var overLimitElsewhere = 0

    private struct Seam: Equatable {
        var due: Double
        var watched = false
    }

    private var seams: [Seam] = []
    private var seamsWatchedBefore = 0
    private var lastPicture: PictureID?
    private var lastChange: Double?
    private var measuringFrom = -Double.infinity

    init(frameDuration: Double) {
        self.frameDuration = frameDuration
    }

    /// Seams that fell inside a measured interval.
    var seamsWatched: Int {
        seamsWatchedBefore + seams.count { $0.watched }
    }

    /// A pass's first frame is due on screen at this host time.
    mutating func seam(dueAt time: Double) {
        seams.append(Seam(due: time))
    }

    mutating func observe(_ picture: PictureID?, at time: Double) {
        guard let picture, picture != lastPicture else { return }
        defer {
            lastPicture = picture
            lastChange = time
        }
        guard let since = lastChange, since >= measuringFrom, frameDuration > 0 else { return }

        let gap = (time - since) / frameDuration
        intervals += 1
        largest = max(largest ?? 0, gap)

        // An interval belongs to a seam when it holds the seam, give or take a frame either side.
        let slack = frameDuration
        var atSeam = false
        for index in seams.indices where seams[index].due > since - slack && seams[index].due < time + slack {
            seams[index].watched = true
            atSeam = true
        }
        if atSeam { largestAtSeam = max(largestAtSeam ?? 0, gap) }
        if gap > Self.limit {
            if atSeam { overLimitAtSeams += 1 } else { overLimitElsewhere += 1 }
        }

        // No later interval can hold these any more.
        let gone = seams.filter { $0.due <= time - slack }
        seamsWatchedBefore += gone.count { $0.watched }
        seams.removeAll { $0.due <= time - slack }
    }

    /// The clock stopped or the timeline started again: no interval spans it.
    mutating func interrupt(at time: Double) {
        lastPicture = nil
        lastChange = nil
        measuringFrom = time + Self.settling
    }
}
