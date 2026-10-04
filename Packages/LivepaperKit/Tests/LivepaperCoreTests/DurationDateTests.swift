import Foundation
import Testing
import LivepaperCore

/// Durations on the wall clock: one copy of the arithmetic, which the host, Selection and Restart share.
struct DurationDateTests {
    static let rows: [Row<Duration, TimeInterval>] = [
        Row("whole seconds", .seconds(600), 600),
        Row("milliseconds", .milliseconds(1), 0.001),
        Row("a negative duration", .seconds(-20), -20),
    ]

    @Test(arguments: rows)
    func `a duration is that many seconds`(row: Row<Duration, TimeInterval>) {
        #expect(row.input.timeInterval == row.expected)
    }

    @Test func `a date and a duration make the date that much later`() {
        #expect(Moment.launch + .seconds(600) == Moment.after(600))
        #expect(Moment.launch + .milliseconds(1500) == Moment.after(1.5))
    }
}
