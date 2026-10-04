import Foundation
import Testing
import LivepaperCore
import LivepaperImport

/// The import list under the grid, driven as the app drives it. Candidates, rows and wallpapers are numbered alike,
/// and times are seconds after `Moment.launch`. Row 101 is candidate 1 dropped a second time, and so on.
struct ImportListTests {
    enum Step: Sendable {
        /// One drop of these candidates, on these rows.
        case drop(candidates: [Int], rows: [Int])
        /// The library check answered for row `number`: the wallpaper it already is, or nil.
        case checked(Int, existing: Int?, at: TimeInterval)
        case progress(Int, ImportStage, Double?)
        case imported(Int, at: TimeInterval)
        /// Candidate `number` is already in the library as wallpaper `of`.
        case duplicate(Int, of: Int, at: TimeInterval)
        case failed(Int, any Error, at: TimeInterval = 0)
        case cancel(Int)
        case retry(Int)
        case tick(at: TimeInterval)

        /// Candidates `numbers`, each on the row of its number.
        static func enqueue(_ numbers: ClosedRange<Int>) -> Step {
            .drop(candidates: Array(numbers), rows: Array(numbers))
        }

        /// Candidate `number` again, on row `100 + number`.
        static func enqueueAgain(_ number: Int) -> Step {
            .drop(candidates: [number], rows: [100 + number])
        }
    }

    /// A row as the test sees it: its number and its state.
    struct Shown: Equatable, Sendable {
        var number: Int
        var state: ImportList.RowState

        static func waiting(_ number: Int) -> Shown {
            Shown(number: number, state: .waiting)
        }

        static func running(
            _ number: Int, _ stage: ImportStage = .fingerprint, _ words: String = "Checking", _ fraction: Double? = nil
        ) -> Shown {
            Shown(number: number, state: .running(stage: stage, words: words, fraction: fraction))
        }

        static func finished(_ number: Int, at seconds: TimeInterval) -> Shown {
            Shown(number: number, state: .finished(.numbered(number), at: Moment.after(seconds)))
        }

        static func duplicate(_ number: Int, of wallpaper: Int, at seconds: TimeInterval) -> Shown {
            Shown(number: number, state: .duplicate(of: .numbered(wallpaper), at: Moment.after(seconds)))
        }

        static func failed(_ number: Int, _ reason: String, canRetry: Bool, at seconds: TimeInterval = 0) -> Shown {
            Shown(number: number, state: .failed(reason: reason, canRetry: canRetry, at: Moment.after(seconds)))
        }
    }

    struct Outcome: Equatable, Sendable {
        var rows: [Shown]
        /// What the last step asked of the app.
        var effects: [ImportList.Effect]
    }

    /// Plays the steps on an empty list.
    static func play(_ steps: [Step]) -> (list: ImportList, effects: [ImportList.Effect]) {
        var list = ImportList()
        var effects: [ImportList.Effect] = []
        for step in steps {
            switch step {
            case .drop(let candidates, let rows):
                effects = list.enqueue(candidates.map(ImportCandidate.numbered), ids: rows.map(UUID.row))
            case .checked(let number, let existing, let seconds):
                effects = list.checked(.row(number), existing: existing.map { .numbered($0) }, at: Moment.after(seconds))
            case .progress(let number, let stage, let fraction):
                effects = list.received(.progress(ImportProgress(stage: stage, fraction: fraction)), for: .row(number), at: Moment.launch)
            case .imported(let number, let seconds):
                effects = list.received(.finished(.imported(.numbered(number), report)), for: .row(number), at: Moment.after(seconds))
            case .duplicate(let number, let wallpaper, let seconds):
                effects = list.received(.finished(.duplicate(of: .numbered(wallpaper))), for: .row(number), at: Moment.after(seconds))
            case .failed(let number, let error, let seconds):
                effects = list.failed(.row(number), error: error, at: Moment.after(seconds))
            case .cancel(let number):
                effects = list.cancel(.row(number))
            case .retry(let number):
                effects = list.retry(.row(number))
            case .tick(let seconds):
                effects = list.tick(at: Moment.after(seconds))
            }
        }
        return (list, effects)
    }

    static let scenarios: [Row<[Step], Outcome>] = [
        Row(
            "several candidates: the first starts, the rest wait and are looked for in the library at once",
            [.enqueue(1...3)],
            Outcome(rows: [.running(1), .waiting(2), .waiting(3)], effects: [.starts(1), .checks(2), .checks(3)])
        ),
        Row(
            "more candidates while one runs: they wait and are looked for, and nothing more starts",
            [.enqueue(1...1), .enqueue(2...3)],
            Outcome(rows: [.running(1), .waiting(2), .waiting(3)], effects: [.checks(2), .checks(3)])
        ),
        Row(
            "progress: the stage in words, and how far through it",
            [.enqueue(1...2), .progress(1, .normalise, 0.42)],
            Outcome(rows: [.running(1, .normalise, "Optimising", 0.42), .waiting(2)], effects: [])
        ),
        Row(
            "a stage that cannot tell how far it is",
            [.enqueue(1...1), .progress(1, .normalise, 0.42), .progress(1, .validate, nil)],
            Outcome(rows: [.running(1, .validate, "Checking the loop")], effects: [])
        ),
        Row(
            "progress for a row that is not running changes nothing",
            [.enqueue(1...2), .progress(2, .normalise, 0.5)],
            Outcome(rows: [.running(1), .waiting(2)], effects: [])
        ),

        Row(
            "imported: the row is finished, and the next starts",
            [.enqueue(1...2), .imported(1, at: 10)],
            Outcome(rows: [.finished(1, at: 10), .running(2)], effects: [.starts(2)])
        ),
        Row(
            "a duplicate: nothing was imported, its toast names what it already is, and the next starts",
            [.enqueue(1...2), .duplicate(1, of: 7, at: 10)],
            Outcome(rows: [.duplicate(1, of: 7, at: 10), .running(2)], effects: [.toasts(.alreadyThere, alreadyHarbour7), .starts(2)])
        ),
        Row(
            "the last import ending starts nothing",
            [.enqueue(1...1), .imported(1, at: 10)],
            Outcome(rows: [.finished(1, at: 10)], effects: [])
        ),
        Row(
            "a finished row takes no more progress",
            [.enqueue(1...2), .imported(1, at: 10), .progress(1, .commit, nil)],
            Outcome(rows: [.finished(1, at: 10), .running(2)], effects: [])
        ),

        Row(
            "a failure: the reason in words, a toast that says why, and the next starts",
            [.enqueue(1...2), .failed(1, ImportError.rejected(.protected))],
            Outcome(
                rows: [.failed(1, "It is copy-protected", canRetry: false), .running(2)],
                effects: [.toasts(.notImported, "“Harbour 1” was not imported. It is copy-protected."), .starts(2)]
            )
        ),
        Row(
            "a cancel that comes back as an error: the row goes, says nothing, and the next starts",
            [.enqueue(1...2), .failed(1, CancellationError())],
            Outcome(rows: [.running(2)], effects: [.starts(2)])
        ),
        Row(
            "an error for a row that is not running changes nothing",
            [.enqueue(1...2), .failed(2, unreadable)],
            Outcome(rows: [.running(1), .waiting(2)], effects: [])
        ),

        Row(
            "cancelling the running import drops its stream, and the next starts",
            [.enqueue(1...3), .cancel(1)],
            Outcome(rows: [.running(2), .waiting(3)], effects: [.cancels(1), .starts(2)])
        ),
        Row(
            "cancelling the last import leaves nothing to start",
            [.enqueue(1...1), .cancel(1)],
            Outcome(rows: [], effects: [.cancels(1)])
        ),
        Row(
            "cancelling a waiting row removes it and drops its check, and nothing else",
            [.enqueue(1...3), .cancel(2)],
            Outcome(rows: [.running(1), .waiting(3)], effects: [.cancels(2)])
        ),
        Row(
            "an outcome that arrives after the cancel is ignored",
            [.enqueue(1...2), .cancel(1), .imported(1, at: 10)],
            Outcome(rows: [.running(2)], effects: [])
        ),
        Row(
            "so is the cancel coming back as an error",
            [.enqueue(1...2), .cancel(1), .failed(1, CancellationError())],
            Outcome(rows: [.running(2)], effects: [])
        ),
        Row(
            "cancel dismisses a failed row",
            [.enqueue(1...1), .failed(1, unreadable), .cancel(1)],
            Outcome(rows: [], effects: [])
        ),

        Row(
            "retry: the failed row starts again when nothing runs",
            [.enqueue(1...1), .failed(1, unreadable), .retry(1)],
            Outcome(rows: [.running(1)], effects: [.starts(1)])
        ),
        Row(
            "retry while another runs: it waits its turn, where it is",
            [.enqueue(1...2), .failed(1, unreadable), .retry(1)],
            Outcome(rows: [.waiting(1), .running(2)], effects: [])
        ),
        Row(
            "the list runs top to bottom, so a retried row goes before the rows below it",
            [.enqueue(1...3), .failed(1, unreadable), .retry(1), .imported(2, at: 10)],
            Outcome(rows: [.running(1), .finished(2, at: 10), .waiting(3)], effects: [.starts(1)])
        ),
        Row(
            "retry of a row that has not failed changes nothing",
            [.enqueue(1...2), .retry(2)],
            Outcome(rows: [.running(1), .waiting(2)], effects: [])
        ),

        Row(
            "a finished row leaves 5 s after it finished",
            [.enqueue(1...2), .imported(1, at: 10), .tick(at: 15)],
            Outcome(rows: [.running(2)], effects: [])
        ),
        Row(
            "and not before",
            [.enqueue(1...2), .imported(1, at: 10), .tick(at: 14.9)],
            Outcome(rows: [.finished(1, at: 10), .running(2)], effects: [])
        ),
        Row(
            "a duplicate leaves likewise",
            [.enqueue(1...1), .duplicate(1, of: 7, at: 10), .tick(at: 15)],
            Outcome(rows: [], effects: [])
        ),
        Row(
            "each finished row on its own time",
            [.enqueue(1...3), .imported(1, at: 10), .imported(2, at: 12), .tick(at: 15)],
            Outcome(rows: [.finished(2, at: 12), .running(3)], effects: [])
        ),
        Row(
            "a failed row that Retry can help stays, for its Retry",
            [.enqueue(1...1), .failed(1, unreadable), .tick(at: 3600)],
            Outcome(rows: [.failed(1, "It could not be read", canRetry: true)], effects: [])
        ),
        Row(
            "a failed row that Retry cannot help leaves 5 s after it failed, as a finished row does: its toast said why",
            [.enqueue(1...2), .failed(1, ImportError.rejected(.protected), at: 10), .tick(at: 15)],
            Outcome(rows: [.running(2)], effects: [])
        ),
        Row(
            "and not before",
            [.enqueue(1...2), .failed(1, ImportError.rejected(.protected), at: 10), .tick(at: 14.9)],
            Outcome(rows: [.failed(1, "It is copy-protected", canRetry: false, at: 10), .running(2)], effects: [])
        ),

        Row(
            "a retried row that fails again keeps the time of the second failure",
            [
                .enqueue(1...1), .failed(1, unreadable, at: 10), .retry(1),
                .failed(1, ImportError.rejected(.protected), at: 20), .tick(at: 24),
            ],
            Outcome(rows: [.failed(1, "It is copy-protected", canRetry: false, at: 20)], effects: [])
        ),
    ]

    /// Wallpaper 7's name, as a duplicate's toast gives it.
    static let alreadyHarbour7 = "Already in the library as “Harbour 7”"

    @Test(arguments: scenarios)
    func `runs one import at a time`(row: Row<[Step], Outcome>) {
        Self.expect(row)
    }

    /// Plays the row's steps and checks the rows and the last effects, and that each row shows its own candidate.
    static func expect(_ row: Row<[Step], Outcome>, sourceLocation: SourceLocation = #_sourceLocation) {
        let (list, effects) = play(row.input)

        let shown = list.rows.map { listed in
            Shown(number: (1...199).first { UUID.row($0) == listed.id } ?? 0, state: listed.state)
        }
        #expect(Outcome(rows: shown, effects: effects) == row.expected, sourceLocation: sourceLocation)
        #expect(
            list.rows.map(\.candidate) == shown.map { .numbered($0.number % 100) }, "each row shows its own candidate",
            sourceLocation: sourceLocation
        )
    }
}

// The status line's count, and when rows leave.
extension ImportListTests {
    // As the Gallery's status line counts: "Importing 1 of 5", "2 of 5", "3 of 5".
    static let progress: [Row<[Step], [Int]?>] = [
        Row("nothing to do", [], nil),
        Row("the first of three", [.enqueue(1...3)], [1, 3]),
        Row("the second of three, once the first has finished", [.enqueue(1...3), .imported(1, at: 10)], [2, 3]),
        Row("still the second of three when the finished row has left", [.enqueue(1...3), .imported(1, at: 10), .tick(at: 15)], [2, 3]),
        Row(
            "a duplicate and a failure are done with too",
            [.enqueue(1...3), .duplicate(1, of: 7, at: 10), .failed(2, ImportError.rejected(.protected))],
            [3, 3]
        ),
        Row("a cancelled import is not counted", [.enqueue(1...3), .imported(1, at: 10), .cancel(2)], [2, 2]),
        Row("nor is a cancelled waiting one", [.enqueue(1...3), .cancel(3)], [1, 2]),
        Row("more candidates join the count", [.enqueue(1...2), .imported(1, at: 10), .enqueue(3...5)], [2, 5]),
        Row("a retry is one more to do", [.enqueue(1...2), .failed(1, unreadable), .retry(1)], [2, 3]),
        Row("nothing running once the last has finished", [.enqueue(1...1), .imported(1, at: 10)], nil),
        Row("the next drop counts from one again", [.enqueue(1...1), .imported(1, at: 10), .enqueue(2...3)], [1, 2]),
        Row("so does a retry after the list went quiet", [.enqueue(1...1), .failed(1, unreadable), .retry(1)], [1, 1]),
        Row("a file refused as already listed is not counted", [.enqueue(1...2), .enqueueAgain(2)], [1, 2]),
        Row("nor is one the library had before its turn", [.enqueue(1...3), .checked(3, existing: 7, at: 5)], [1, 2]),
    ]

    @Test(arguments: progress)
    func `says which import of how many is running`(row: Row<[Step], [Int]?>) {
        let list = Self.play(row.input).list

        #expect(list.progress.map { [$0.position, $0.count] } == row.expected)
        #expect(list.isRunning == (row.expected != nil))
    }

    static let ticks: [Row<[Step], TimeInterval?>] = [
        Row("nothing finished: no tick is wanted", [.enqueue(1...2)], nil),
        Row("the first finished row to leave", [.enqueue(1...3), .imported(1, at: 10), .duplicate(2, of: 7, at: 12)], 15),
        Row("then the next", [.enqueue(1...3), .imported(1, at: 10), .duplicate(2, of: 7, at: 12), .tick(at: 15)], 17),
        Row("a failed row that Retry can help never leaves by itself", [.enqueue(1...1), .failed(1, unreadable)], nil),
        Row(
            "a failed row that Retry cannot help leaves 5 s after it failed",
            [.enqueue(1...3), .failed(1, ImportError.rejected(.protected), at: 10), .imported(2, at: 12)],
            15
        ),
    ]

    @Test(arguments: ticks)
    func `says when a tick next has something to do`(row: Row<[Step], TimeInterval?>) {
        #expect(Self.play(row.input).list.nextTick == row.expected.map(Moment.after))
    }
}

// What the steps feed the list.
extension ImportListTests {
    /// A failure Retry can help with: "It could not be read".
    static let unreadable = MediaError.readFailed("unknown")

    static let report = ImportReport(
        plan: .remux,
        writtenBy: .remux,
        seam: judgeLoopSeam(TrackReading(
            timescale: 600, frames: [TrackReading.Frame(pts: 0, duration: 20, isSync: true)], trackDuration: 20, hasEditList: false
        ))
    )
}

extension ImportList.Effect {
    static func starts(_ number: Int) -> Self {
        .start(.row(number), .numbered(number % 100))
    }

    static func checks(_ number: Int) -> Self {
        .check(.row(number), .numbered(number % 100))
    }

    static func cancels(_ number: Int) -> Self {
        .cancel(.row(number))
    }

    static func toasts(_ kind: ImportToast.Kind, _ words: String) -> Self {
        .toast(ImportToast(kind: kind, words: words))
    }
}
