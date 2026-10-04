import Foundation
import LivepaperCore
import LivepaperSystem
import Testing

/// What the store's shape check tells the host and the diagnostics report, and the name "Save…" gives a report.
struct DiagnosticsInputsTests {
    static let selections: [Row<WallpaperStoreShape.Store, StoreSelection>] = [
        Row("every Desktop entry naming Livepaper is selected", .read(desktopEntries: 24, namingLivepaper: 24), .selected),
        Row("one Desktop entry naming it is selected", .read(desktopEntries: 24, namingLivepaper: 1), .selected),
        Row("none naming it is not selected", .read(desktopEntries: 2, namingLivepaper: 0), .notSelected),
        Row("a store with no Desktop entry is not selected", .read(desktopEntries: 0, namingLivepaper: 0), .notSelected),
        Row("an unreadable store cannot say", .unreadable, .unreadable),
        Row("a store of a shape this build does not know cannot say", .unknownShape, .unreadable),
    ]

    @Test(arguments: selections)
    func `whether the store names Livepaper at all`(row: Row<WallpaperStoreShape.Store, StoreSelection>) {
        #expect(WallpaperStoreShape(store: row.input, keptCopyExists: false).selection == row.expected)
    }

    @Test func `a saved report is plain text named by when it was made, in the user's time zone`() throws {
        let london = try #require(TimeZone(identifier: "Europe/London"))
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        // 2026-09-24 13:05:09 UTC.
        let made = Date(timeIntervalSince1970: 1_790_255_109)

        #expect(DiagnosticsReport.fileName(madeAt: made, timeZone: london) == "Livepaper Diagnostics 2026-09-24 at 14.05.09.txt")
        #expect(DiagnosticsReport.fileName(madeAt: made, timeZone: tokyo) == "Livepaper Diagnostics 2026-09-24 at 22.05.09.txt")
    }
}
