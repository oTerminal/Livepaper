import LivepaperCore
import LivepaperSystem
import LivepaperTestSupport
import Testing

/// When the window list is read for the covered displays: at the start, 0.25 s
/// and 1 s after an event, and every second while covering pauses the
/// wallpaper and a display is covered or Show Desktop has the windows aside.
/// Nothing tells an app that Show Desktop or a moved window uncovered a
/// display (found on screen: the hot corner). A read that never comes
/// fails the test at the time limit instead of hanging the run.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct CoveredDisplayReaderTests {
    /// The window list, saying what the test sets, and counting its reads.
    final class WindowList {
        var now = WindowListReading()
        private(set) var reads = 0

        func read() -> WindowListReading {
            reads += 1
            return now
        }
    }

    final class Reports {
        private(set) var all: [Set<DisplayIdentity>] = []

        func append(_ covered: Set<DisplayIdentity>) {
            all.append(covered)
        }
    }

    static let one = DisplayIdentity.numbered(1)
    static let covered = WindowListReading(covered: [one])
    static let uncovered = WindowListReading()
    static let showingDesktop = WindowListReading(showingDesktop: true)

    let clock = ManualClock(start: Moment.launch)
    let windowList = WindowList()
    let reports = Reports()
    let reader: CoveredDisplayReader<ManualClock>

    init() {
        reader = CoveredDisplayReader(clock: clock, read: windowList.read, report: reports.append)
    }

    /// The next read, in milliseconds since the start; nil when none is due.
    var nextRead: Int? {
        reader.nextRead.map { Int($0.offset / .milliseconds(1)) }
    }

    /// Lets the reader's task run until `condition` holds, or gives up.
    func settle(until condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
    }

    /// Moves the clock to `milliseconds` since the start and lets the read that falls due there run.
    func advance(toMillisecond milliseconds: Int) async {
        clock.advance(by: .milliseconds(milliseconds) - clock.now.offset)
        await settle { reader.nextRead.map { $0 > clock.now } ?? true }
    }

    /// Lets the reader run, so that a read that should not come has had every chance to.
    func noMoreReads(than reads: Int) async {
        await settle { windowList.reads > reads }
        #expect(windowList.reads == reads)
    }

    @Test func `the start reads the window list and reports what it finds`() {
        windowList.now = Self.covered

        reader.start()

        #expect(windowList.reads == 1)
        #expect(reports.all == [[Self.one]])
    }

    @Test func `while a display is covered, the window list is read again every second`() async {
        reader.coveringPauses = true
        windowList.now = Self.covered
        reader.start()
        #expect(nextRead == 1000)

        await advance(toMillisecond: 1000)
        #expect(windowList.reads == 2)
        #expect(nextRead == 2000)
        await advance(toMillisecond: 2000)

        #expect(windowList.reads == 3)
        #expect(nextRead == 3000)
        #expect(reports.all == [[Self.one]])
    }

    @Test func `uncovering is reported at the next read, and the reads stop there`() async {
        reader.coveringPauses = true
        windowList.now = Self.covered
        reader.start()

        windowList.now = Self.uncovered
        await advance(toMillisecond: 1000)

        #expect(reports.all == [[Self.one], []])
        #expect(nextRead == nil)
        await settle { clock.sleeperCount == 0 }
        #expect(clock.sleeperCount == 0)
        await advance(toMillisecond: 60000)
        await noMoreReads(than: 2)
    }

    @Test func `with nothing covered, nothing is read until something happens`() async {
        reader.coveringPauses = true
        reader.start()

        #expect(nextRead == nil)
        await advance(toMillisecond: 3_600_000)
        await noMoreReads(than: 1)
        #expect(reports.all == [[]])
    }

    @Test func `after an event the list is read at 0.25 s and 1 s, and a covering is reported at the first`() async {
        reader.coveringPauses = true
        reader.start()

        windowList.now = Self.covered
        reader.somethingMoved()
        #expect(nextRead == 250)
        await advance(toMillisecond: 250)
        #expect(reports.all == [[], [Self.one]])
        #expect(nextRead == 1000)
        await advance(toMillisecond: 1000)

        #expect(windowList.reads == 3)
        #expect(nextRead == 2000)
    }

    @Test func `a burst of events is read once, after the last of them`() async {
        reader.start()
        reader.somethingMoved()
        await advance(toMillisecond: 200)

        reader.somethingMoved()
        #expect(nextRead == 450)
        await advance(toMillisecond: 450)

        #expect(windowList.reads == 2)
        #expect(nextRead == 1200)
    }

    @Test func `the hot corner's Show Desktop is seen within a second, and so is the windows' return`() async {
        reader.coveringPauses = true
        windowList.now = Self.covered
        reader.start()

        // The windows slide aside; no notification says so.
        windowList.now = Self.showingDesktop
        await advance(toMillisecond: 1000)
        #expect(reports.all == [[Self.one], []])
        #expect(nextRead == 2000)

        // They slide back; no notification says that either.
        windowList.now = Self.covered
        await advance(toMillisecond: 2000)

        #expect(reports.all == [[Self.one], [], [Self.one]])
        #expect(nextRead == 2250)
    }

    @Test func `the end of Show Desktop is read again as an event is, since its window goes before the windows are back`() async {
        reader.coveringPauses = true
        windowList.now = Self.showingDesktop
        reader.start()

        // WindowManager's window has left the list; the windows are still sliding back.
        windowList.now = Self.uncovered
        await advance(toMillisecond: 1000)
        #expect(nextRead == 1250)
        windowList.now = Self.covered
        await advance(toMillisecond: 1250)

        #expect(reports.all == [[], [Self.one]])
        #expect(nextRead == 2000)
    }

    @Test func `with covering pausing nothing, a covered display is read only after events`() async {
        windowList.now = Self.covered
        reader.start()
        #expect(nextRead == nil)

        reader.somethingMoved()
        await advance(toMillisecond: 250)
        await advance(toMillisecond: 1000)

        #expect(windowList.reads == 3)
        #expect(nextRead == nil)
    }

    @Test func `switching the rule on reads a covered display at once and then every second, and off stops it`() async {
        windowList.now = Self.covered
        reader.start()
        await advance(toMillisecond: 10000)

        reader.coveringPauses = true
        await settle { windowList.reads == 2 }
        #expect(windowList.reads == 2)
        #expect(nextRead == 11000)

        reader.coveringPauses = false
        #expect(nextRead == nil)
        await settle { clock.sleeperCount == 0 }
        #expect(clock.sleeperCount == 0)
    }

    @Test func `stopping cancels the next read, and starting again reports afresh`() async {
        reader.coveringPauses = true
        windowList.now = Self.covered
        reader.start()

        reader.stop()
        #expect(nextRead == nil)
        await advance(toMillisecond: 5000)
        await noMoreReads(than: 1)

        reader.start()
        #expect(reports.all == [[Self.one], [Self.one]])
    }
}
