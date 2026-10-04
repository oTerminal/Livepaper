import Foundation
import Testing
import LivepaperCore

/// A host status has one name, which the logs, the socket's `status` and the
/// diagnostics use, and one set of words, which the popover and the tool say.
struct RenderHostStatusWordsTests {
    static let names: [Row<RenderHostStatus, String>] = [
        Row("stopped", .stopped, "stopped"),
        Row("connecting", .connecting, "connecting"),
        Row("not selected", .notSelected, "notSelected"),
        Row("live", .live, "live"),
        Row("recovering names its level", .recovering(.rebuildSurface), "recovering(rebuildSurface)"),
        Row("recovering by restarting the agent", .recovering(.restartAgent), "recovering(restartAgent)"),
        Row("unavailable", .unavailable, "unavailable"),
    ]

    @Test(arguments: names)
    func `a status is named as it is spelled`(row: Row<RenderHostStatus, String>) {
        #expect(row.input.name == row.expected)
    }

    static let words: [Row<RenderHostStatus, String>] = [
        Row("stopped", .stopped, "Stopped"),
        Row("connecting", .connecting, "Connecting to the wallpaper service"),
        Row("not selected", .notSelected, "Livepaper is not your wallpaper"),
        Row("live", .live, "Live"),
        Row("recovering, whatever the level", .recovering(.flush), "Recovering the wallpaper"),
        Row("unavailable", .unavailable, "Not available on this version of macOS"),
    ]

    @Test(arguments: words)
    func `a status is said in words`(row: Row<RenderHostStatus, String>) {
        #expect(row.input.words == row.expected)
    }

    static let shared: [RenderHostStatus] = [.connecting, .notSelected, .recovering(.flush), .unavailable]

    @Test(arguments: shared)
    func `the status line and the tool say a status in the same words`(host: RenderHostStatus) {
        let report = StatusReport(host: host, displays: [], wallpapers: [], playlists: [], isPausedAll: false, isMuted: false)
        let printed = CommandLineOutput(.status(report), json: false).standardOutput
        let line = statusLine(host: host, showing: 1, isPausedAll: false, importing: nil)

        #expect(line == .idle(host.words) || line == .working(host.words))
        #expect(printed.hasPrefix("Status: \(host.words)\n"))
    }
}
