import Foundation
import LivepaperCore
@testable import LivepaperSystem
import Testing

/// The extension's lines for the diagnostics report: `log show` on its subsystem alone.
/// Only the report reads them, redacted, so what is tested here is internal.
@Suite(.timeLimit(.minutes(1)))
struct ExtensionLogLinesTests {
    static func entry(
        _ message: String, category: String = "supervisor", level: String = "Default", at time: String = "11:58:38.677991"
    ) -> String {
        #"{"subsystem":"app.livepaper.extension","category":"\#(category)","messageType":"\#(level)","#
            + #""timestamp":"2026-09-24 \#(time)+0100","processImagePath":"\/Users\/someone\/x","eventMessage":"\#(message)"}"#
    }

    static let trailer = #"{"count":2,"finished":1}"#

    @Test func `the query asks log show for the extension's subsystem over the last ten minutes`() {
        #expect(ExtensionLogLines.recentArguments(subsystem: "app.livepaper.extension") == [
            "show", "--last", "10m", "--style", "ndjson", "--predicate", #"subsystem == "app.livepaper.extension""#,
        ])
    }

    @Test func `the self-check is looked for since the Mac started`() {
        #expect(ExtensionLogLines.selfCheckArguments(subsystem: "app.livepaper.extension") == [
            "show", "--last", "boot", "--style", "ndjson", "--predicate",
            #"subsystem == "app.livepaper.extension" AND category == "bridge" AND eventMessage BEGINSWITH "bridge self-check""#,
        ])
    }

    @Test func `each entry becomes its time, level, category and message, and the trailer is left out`() {
        let output = [
            Self.entry("render state read generation=4 stopped=false displays=1"),
            Self.entry("bridge self-check: failed, missing: WallpaperExtensionKit", category: "bridge", level: "Error", at: "11:58:39.0"),
            Self.trailer,
        ].joined(separator: "\n")

        let lines = ExtensionLogLines.entries(ndjson: Data(output.utf8))

        #expect(lines.map(\.text) == [
            "2026-09-24 11:58:38.677991+0100 Default [supervisor] render state read generation=4 stopped=false displays=1",
            "2026-09-24 11:58:39.0+0100 Error [bridge] bridge self-check: failed, missing: WallpaperExtensionKit",
        ])
    }

    @Test func `the latest 200 lines are kept`() {
        let output = (1...250).map { Self.entry("line \($0)") }.joined(separator: "\n") + "\n" + Self.trailer

        let lines = ExtensionLogLines(recent: Data(output.utf8), selfChecks: Data()).lines

        #expect(lines.count == 200)
        #expect(lines.first?.message == "line 51" && lines.last?.message == "line 250")
    }

    @Test func `the self-check is the latest one logged`() {
        let checks = [
            Self.entry("bridge self-check: usable, missing: x", category: "bridge"),
            Self.entry("bridge self-check: all present", category: "bridge"),
        ]

        let log = ExtensionLogLines(recent: Data(), selfChecks: Data(checks.joined(separator: "\n").utf8))

        #expect(log.selfCheck?.message == "bridge self-check: all present")
    }

    @Test func `what log show says when it refuses is kept as the problem`() {
        let log = ExtensionLogLines(problem: "log: Must be admin to run 'show' command")

        #expect(log.lines.isEmpty && log.selfCheck == nil)
        #expect(log.problem == "log: Must be admin to run 'show' command")
    }

    // The look back to the Mac's start reads the whole log since boot: on CI's
    // virtual Mac that took its few cores for seconds and starved the rest of the suite.
    @Test(.disabled(if: VirtualMac.isRunning, "log show since boot is too heavy for a virtual Mac's few cores"))
    func `a subsystem nobody logs to gives no lines and no problem`() async {
        let log = await ExtensionLogLines.fetch(subsystem: "app.livepaper.tests.nobody-logs-here")

        #expect(log.problem == nil)
        #expect(log.lines.isEmpty && log.selfCheck == nil)
    }
}
