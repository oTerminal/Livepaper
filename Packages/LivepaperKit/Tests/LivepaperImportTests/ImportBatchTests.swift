import Foundation
import LivepaperCore
import LivepaperImport
import Testing

/// Where a batch of imports started together has got to, read off the import
/// list's rows: the first wallpaper it gave, what is still importing, or why
/// none came. Onboarding's first wallpaper waits on this.
struct ImportBatchTests {
    typealias Step = ImportListTests.Step

    /// Candidates 1 to 3 dropped together, on rows 1 to 3, then these steps.
    static func batch(after steps: [Step], rows: [Int] = [1, 2, 3]) -> ImportBatch {
        ImportListTests.play([.enqueue(1...3)] + steps).list.batch(rows.map(UUID.row))
    }

    static let scenarios: [Row<[Step], ImportBatch>] = [
        Row("just dropped: the first row is running, not yet past its first stage", [], .importing(name: "Harbour 1", words: "Checking")),
        Row(
            "the running row's stage, in words",
            [.progress(1, .normalise, 0.5)], .importing(name: "Harbour 1", words: "Optimising")
        ),
        Row("the first row imported: its wallpaper", [.imported(1, at: 10)], .wallpaper(.numbered(1))),
        Row(
            "the first row a duplicate: the wallpaper it already is",
            [.duplicate(1, of: 7, at: 10)], .wallpaper(.numbered(7))
        ),
        Row(
            "a later row found in the library before the first finished: that one, at once",
            [.checked(2, existing: 8, at: 1)], .wallpaper(.numbered(8))
        ),
        Row(
            "the first row failed: the next is running",
            [.failed(1, ImportListTests.unreadable, at: 5)], .importing(name: "Harbour 2", words: "Checking")
        ),
        Row(
            "the first row failed and the second imported: the second's wallpaper",
            [.failed(1, ImportListTests.unreadable, at: 5), .imported(2, at: 10)], .wallpaper(.numbered(2))
        ),
        Row(
            "two imported: the first in the batch's order",
            [.imported(1, at: 10), .imported(2, at: 20)], .wallpaper(.numbered(1))
        ),
        Row(
            "every row failed: the first failure's reason",
            [
                .failed(1, ImportListTests.unreadable, at: 5),
                .failed(2, MediaError.noVideoTrack, at: 6),
                .failed(3, ImportListTests.unreadable, at: 7),
            ],
            .failed(reason: "It could not be read")
        ),
        Row(
            "every row cancelled, so none is on the list: failed, with nothing to say",
            [.cancel(1), .cancel(2), .cancel(3)], .failed(reason: nil)
        ),
    ]

    @Test(arguments: scenarios)
    func `reads the batch off its rows`(row: Row<[Step], ImportBatch>) {
        #expect(Self.batch(after: row.input) == row.expected)
    }

    @Test func `rows outside the batch are no part of it`() {
        // Row 1 is someone else's import; the batch is rows 2 and 3.
        let imported = Self.batch(after: [.imported(1, at: 10)], rows: [2, 3])
        let waiting = Self.batch(after: [], rows: [2, 3])

        #expect(imported == .importing(name: "Harbour 2", words: "Checking"))
        #expect(waiting == .importing(name: "Harbour 2", words: nil))
    }

    @Test func `a batch the list never had has failed`() {
        #expect(ImportList().batch([.row(1)]) == .failed(reason: nil))
    }
}
