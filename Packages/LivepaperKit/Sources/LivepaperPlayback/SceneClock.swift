import Foundation

/// Scene time: the seconds a scene has been drawn for, which run only while it
/// plays. A pause, a suspend or a recovery stops it where it is,
/// and the next start carries on from there, so a scene resumes where it
/// stopped, as a video does. It is read in the display link's own times, the
/// moments frames are to be shown at, and never runs backwards.
struct SceneClock: Equatable, Sendable {
    /// Scene time when the run under way began.
    private(set) var carried: Double = 0
    /// The scene time of the latest frame.
    private(set) var latest: Double = 0
    private var isRunning = false
    /// The moment the run's first frame is shown at; nil before it.
    private var runStart: Double?

    mutating func start() {
        isRunning = true
        runStart = nil
    }

    /// The scene time of a frame to be shown at `moment`, in the link's seconds.
    /// The first frame of a run shows the time the last run stopped at.
    mutating func time(forFrameAt moment: Double) -> Double {
        guard isRunning else { return latest }
        let start = runStart ?? moment
        runStart = start
        latest = max(latest, carried + max(0, moment - start))
        return latest
    }

    mutating func stop() {
        carried = latest
        isRunning = false
        runStart = nil
    }

    /// Back to the scene's first moment, for another scene or the same one started afresh.
    mutating func reset() {
        self = SceneClock()
    }
}

/// What the scene engine has done since it was made, for the watchdog's counts.
///
/// A scene's pictures are the ones its GPU finished and put on the Metal slot,
/// as a video's are the ones its renderer put on its layer: what the engine
/// itself did, whether or not the window server showed it. The window server's
/// own presented times are kept beside them for the log. Under windows it
/// presents the desktop a few times a second, so judged by
/// them a covered scene could never be healthy while a covered video was.
struct SceneTally: Equatable, Sendable {
    /// Frames the display link asked for.
    var asked = 0
    /// Frames encoded and handed to the GPU: what the engine fed.
    var committed = 0
    /// Frames the GPU finished, onto the slot's drawable: what was displayed.
    var completed = 0
    /// Frames the GPU gave up on.
    var failed = 0
    /// Frames the window server showed, by their presented time. Logged, not judged.
    var presented = 0

    /// Frames the engine can have on the GPU at once without falling behind: its latency of two, and one more.
    static let framesInFlight = 3

    /// The GPU keeps up: no more frames are on it, unfinished, than the engine's latency allows.
    var isGPUKeepingUp: Bool { committed - completed - failed <= Self.framesInFlight }

    /// The watchdog's count over a window between two tallies (`PictureCount`),
    /// at the scene's rate. `engineReady`: at the window's end the link was up,
    /// the render thread answered at once and the GPU kept up, so a link that
    /// asked for too few frames was not asked by the system, which is what a
    /// covered surface looks like.
    static func count(
        from before: SceneTally, to after: SceneTally, over window: Duration, framesPerSecond: Double, engineReady: Bool
    ) -> PictureCount {
        let expected = Int((window / .seconds(1) * framesPerSecond).rounded())
        let asked = after.asked - before.asked
        return PictureCount(
            displayed: after.completed - before.completed,
            expected: expected,
            fed: (after.committed - before.committed) - (after.failed - before.failed),
            asked: asked,
            withheld: engineReady && asked * 2 < expected,
            presented: after.presented - before.presented
        )
    }
}
