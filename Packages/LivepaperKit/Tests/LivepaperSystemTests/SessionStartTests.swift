import Foundation
import LivepaperSystem
import Testing

/// Where the login session's start comes from: the console login in utmpx, else the boot.
struct SessionStartTests {
    static func record(
        _ kind: LoginRecord.Kind, user: String = "someone", line: String = "console", at seconds: TimeInterval
    ) -> LoginRecord {
        LoginRecord(kind: kind, user: user, line: line, time: Moment.after(seconds))
    }

    static let rows: [Row<[LoginRecord], TimeInterval?>] = [
        Row("the user's console login", [record(.boot, line: "", at: -40), record(.userProcess, at: 0)], 0),
        Row(
            "a terminal's login is not the session's",
            [record(.userProcess, at: 0), record(.userProcess, line: "ttys000", at: 3000)],
            0
        ),
        Row("another user's console login is not this one's", [record(.userProcess, user: "other", at: 900)], nil),
        Row("a session that ended is not the one running", [record(.deadProcess, at: 0)], nil),
        Row(
            "logged out and in again: the latest",
            [record(.deadProcess, at: 0), record(.userProcess, at: 0), record(.userProcess, at: 7200)],
            7200
        ),
        Row("no records", [], nil),
    ]

    @Test(arguments: rows)
    func `the session starts at the user's console login`(row: Row<[LoginRecord], TimeInterval?>) {
        #expect(SessionStart.consoleLogin(of: "someone", in: row.input) == row.expected.map(Moment.after))
    }

    @Test func `this Mac answers with a time that has passed`() throws {
        let start = try #require(SessionStart.current())

        #expect(start.date <= Date())
        #expect(start.date > Date(timeIntervalSince1970: 0))
    }
}
