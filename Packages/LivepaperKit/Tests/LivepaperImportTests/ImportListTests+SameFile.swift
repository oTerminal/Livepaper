import Foundation
import Testing
import LivepaperCore
import LivepaperImport

// The same file again, and the library check: said at once, never after the imports ahead of it.
extension ImportListTests {
    static let sameFile: [Row<[Step], Outcome>] = [
        Row(
            "a file already waiting is refused and says so; no row is added",
            [.enqueue(1...2), .enqueueAgain(2)],
            Outcome(rows: [.running(1), .waiting(2)], effects: [.toasts(.alreadyThere, "“Harbour 2” is already in the import list")])
        ),
        Row(
            "a file already running likewise",
            [.enqueue(1...2), .enqueueAgain(1)],
            Outcome(rows: [.running(1), .waiting(2)], effects: [.toasts(.alreadyThere, "“Harbour 1” is already in the import list")])
        ),
        Row(
            "a file that failed likewise: its row has Retry",
            [.enqueue(1...1), .failed(1, unreadable, at: 10), .enqueueAgain(1)],
            Outcome(
                rows: [.failed(1, "It could not be read", canRetry: true, at: 10)],
                effects: [.toasts(.alreadyThere, "“Harbour 1” is already in the import list")]
            )
        ),
        Row(
            "the same file twice in one drop: the second is refused",
            [.drop(candidates: [1, 2, 1], rows: [1, 2, 3])],
            Outcome(
                rows: [.running(1), .waiting(2)],
                effects: [.toasts(.alreadyThere, "“Harbour 1” is already in the import list"), .starts(1), .checks(2)]
            )
        ),
        Row(
            "a file whose row has finished waits again, and is looked for in the library",
            [.enqueue(1...2), .imported(1, at: 10), .enqueueAgain(1)],
            Outcome(rows: [.finished(1, at: 10), .running(2), .waiting(101)], effects: [.checks(101)])
        ),
        Row(
            "a waiting file the library has is a duplicate at once, its toast says so, and the running import carries on",
            [.enqueue(1...3), .checked(3, existing: 7, at: 5)],
            Outcome(rows: [.running(1), .waiting(2), .duplicate(3, of: 7, at: 5)], effects: [.toasts(.alreadyThere, alreadyHarbour7)])
        ),
        Row(
            "a waiting file the library does not have waits on",
            [.enqueue(1...2), .checked(2, existing: nil, at: 5)],
            Outcome(rows: [.running(1), .waiting(2)], effects: [])
        ),
        Row(
            "an answer for the running import changes nothing: it finds out for itself",
            [.enqueue(1...2), .checked(1, existing: 7, at: 5)],
            Outcome(rows: [.running(1), .waiting(2)], effects: [])
        ),
        Row(
            "an answer for a cancelled row changes nothing",
            [.enqueue(1...2), .cancel(2), .checked(2, existing: 7, at: 5)],
            Outcome(rows: [.running(1)], effects: [])
        ),
        Row(
            "a duplicate found before its turn leaves 5 s later, as a finished row does",
            [.enqueue(1...2), .checked(2, existing: 7, at: 5), .tick(at: 10)],
            Outcome(rows: [.running(1)], effects: [])
        ),
        Row(
            "the running import ending passes over it",
            [.enqueue(1...3), .checked(2, existing: 7, at: 5), .imported(1, at: 10)],
            Outcome(rows: [.finished(1, at: 10), .duplicate(2, of: 7, at: 5), .running(3)], effects: [.starts(3)])
        ),
    ]

    @Test(arguments: sameFile)
    func `says at once that a file is on the list or in the library already`(row: Row<[Step], Outcome>) {
        Self.expect(row)
    }
}

// What a row offers, whatever its state.
extension ImportListTests {
    struct Offers: Equatable, Sendable {
        var canCancel = false
        var canRetry = false
        var canRemove = false
        /// The wallpaper whose poster stands in the row.
        var wallpaper: Int?
    }

    static let offers: [Row<ImportList.RowState, Offers>] = [
        Row("waiting: Cancel", .waiting, Offers(canCancel: true)),
        Row("running: Cancel", .running(stage: .normalise, words: "Optimising", fraction: 0.5), Offers(canCancel: true)),
        Row("finished: the wallpaper it made", .finished(.numbered(7), at: Moment.launch), Offers(wallpaper: 7)),
        Row("a duplicate: the wallpaper it already is", .duplicate(of: .numbered(7), at: Moment.launch), Offers(wallpaper: 7)),
        Row(
            "failed where Retry can help: Retry, or taken off the list",
            .failed(reason: "It could not be read", canRetry: true, at: Moment.launch),
            Offers(canRetry: true, canRemove: true)
        ),
        Row(
            "failed where Retry cannot help: nothing, it leaves by itself",
            .failed(reason: "It is copy-protected", canRetry: false, at: Moment.launch),
            Offers()
        ),
    ]

    @Test(arguments: offers)
    func `a row offers what its state allows`(row: Row<ImportList.RowState, Offers>) {
        let state = row.input
        let wallpaper = state.wallpaper.map { wallpaper in (1...99).first { Wallpaper.numbered($0) == wallpaper } ?? 0 }

        let offers = Offers(canCancel: state.canCancel, canRetry: state.canRetry, canRemove: state.canRemove, wallpaper: wallpaper)

        #expect(offers == row.expected)
    }
}
