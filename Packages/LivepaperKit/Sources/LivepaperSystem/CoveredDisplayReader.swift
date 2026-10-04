import LivepaperCore

/// When the window list is read for the covered displays, and what is
/// reported from it: the covered displays at the start, then each time a read
/// finds them changed.
///
/// The list is read at the start; after each of `settles`, counted from an
/// event that can cover or uncover a display (`somethingMoved`) or from the
/// read that found Show Desktop over; and, while covering pauses the
/// wallpaper, every `interval` for as long as the last read found a display
/// covered or Show Desktop on. None of the events says that Show Desktop moved
/// the windows aside or back, or that a window was dragged or resized: a
/// covered display is looked at until it is uncovered, since a paused
/// wallpaper that should play is what the user sees, and the windows Show
/// Desktop moved aside until they come back. Otherwise nothing is read until
/// the next event: a display covered by hand plays under its
/// window until then, which costs energy but looks right.
public final class CoveredDisplayReader<C: Clock<Duration>> {
    public let clock: C
    public let settles: [Duration]
    public let interval: Duration
    /// Whether a covered display pauses the wallpaper: the "Desktop fully
    /// covered" rule. Without it, nothing is read on the interval.
    public var coveringPauses = false {
        didSet { arm() }
    }

    private let read: () -> WindowListReading
    private let report: (Set<DisplayIdentity>) -> Void
    private var last: (reading: WindowListReading, at: C.Instant)?
    private var settling: [C.Instant] = []
    private var armed: (at: C.Instant, task: Task<Void, Never>)?

    /// - Parameters:
    ///   - settles: after an event, the list is read once the window has
    ///     started to move and once a fullscreen transition has had time to
    ///     finish. On macOS 27 the Space change comes as the fullscreen
    ///     animation ends, and the fullscreen window is in the list 0.06 s
    ///     later, the Dock's gone 0.17 s later, so both reads see it.
    ///   - interval: how often a covered display is looked at. Show Desktop
    ///     has its windows out of the way 0.1 s after it starts, so uncovering
    ///     is seen within about a second. A read takes about 2 ms, most of it
    ///     in the window server, against a paused wallpaper's decoder.
    public init(
        clock: C,
        settles: [Duration] = [.milliseconds(250), .milliseconds(1000)],
        interval: Duration = .seconds(1),
        read: @escaping () -> WindowListReading,
        report: @escaping (Set<DisplayIdentity>) -> Void
    ) {
        self.clock = clock
        self.settles = settles
        self.interval = interval
        self.read = read
        self.report = report
    }

    /// When the list is read next: the next of an event's reads, or, while
    /// covering pauses and the last read found a display covered or Show
    /// Desktop on, `interval` after that read; nil while neither is due.
    public var nextRead: C.Instant? {
        var next = settling.min()
        if coveringPauses, let last, !last.reading.covered.isEmpty || last.reading.showingDesktop {
            let again = last.at.advanced(by: interval)
            next = next.map { min($0, again) } ?? again
        }
        return next
    }

    /// Reads the list now and reports what it finds.
    public func start() {
        readNow()
    }

    /// Reads nothing more until the next start, and forgets what was read.
    public func stop() {
        armed?.task.cancel()
        armed = nil
        settling = []
        last = nil
    }

    /// Something happened that can cover or uncover a display: reads the list
    /// after each of `settles`, instead of after the event before, so that a
    /// burst of events is read once, after the last of them.
    public func somethingMoved() {
        let now = clock.now
        settling = settles.map { now.advanced(by: $0) }
        arm()
    }

    private func readNow() {
        let now = clock.now
        settling.removeAll { $0 <= now }
        let reading = read()
        let changed = reading.covered != last?.reading.covered
        // Show Desktop's window leaves the list about 0.1 s before the windows
        // are back, so its end is read again as an event is.
        if last?.reading.showingDesktop == true, !reading.showingDesktop {
            settling = settles.map { now.advanced(by: $0) }
        }
        last = (reading, now)
        if changed { report(reading.covered) }
        arm()
    }

    private func arm() {
        let next = nextRead
        guard next != armed?.at else { return }
        armed?.task.cancel()
        armed = nil
        guard let next else { return }
        // Leeway lets the system fire the read alongside other timers. A read
        // re-armed after its sleep ended, but before it ran, is cancelled too.
        armed = (next, Task { [weak self, clock] in
            do {
                try await clock.sleep(until: next, tolerance: .milliseconds(100))
                try Task.checkCancellation()
            } catch {
                return
            }
            self?.readDue()
        })
    }

    private func readDue() {
        armed = nil
        readNow()
    }
}
