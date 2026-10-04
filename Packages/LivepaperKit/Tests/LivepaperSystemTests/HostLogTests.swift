import Foundation
import LivepaperCore
import LivepaperSystem
import Testing

/// Other tools read these lines, so each recovery level's wording is pinned.
struct HostLogTests {
    static let rows: [Row<String, String>] = [
        Row("silence asks for a flush", HostLog.silence(.flush), "host: no heartbeat, asking the extension to flush"),
        Row(
            "silence asks for a rebuilt surface",
            HostLog.silence(.rebuildSurface),
            "host: no heartbeat, asking the extension to rebuildSurface"
        ),
        Row("the app asks for a rebuilt pipeline", HostLog.recover(.rebuildPipeline), "host: asking the extension to rebuildPipeline"),
        Row("the app asks for a flush", HostLog.recover(.flush), "host: asking the extension to flush"),
        Row(
            "a level skipped before the first heartbeat",
            HostLog.skipped(.rebuildPipeline),
            "host: no heartbeat since activation, skipping rebuildPipeline: no extension to receive it"
        ),
        Row("recovering names its level", HostLog.status(.recovering(.rebuildSurface)), "host: status recovering(rebuildSurface)"),
        Row("recovering by restarting the agent", HostLog.status(.recovering(.restartAgent)), "host: status recovering(restartAgent)"),
    ]

    @Test(arguments: rows)
    func `a recovery level is named as it is spelled`(row: Row<String, String>) {
        #expect(row.input == row.expected)
    }

    static let restartsAndStatus: [Row<String, String>] = [
        Row("activation", HostLog.activated, "host: activated, waiting for the extension's heartbeat"),
        Row("live", HostLog.status(.live), "host: status live"),
        Row("not selected", HostLog.status(.notSelected), "host: status notSelected"),
        Row("unavailable", HostLog.status(.unavailable), "host: status unavailable"),
        Row("a restart for silence", HostLog.restarting(.silence), "host: restarting WallpaperAgent (silence)"),
        Row("a restart the user asked for", HostLog.restarting(.user), "host: restarting WallpaperAgent (user)"),
        Row(
            "the agent came back",
            HostLog.restarted(.restarted(previous: 62873, current: 61187)),
            "host: WallpaperAgent restarted, pid 62873 -> 61187"
        ),
        Row(
            "the agent is not back yet",
            HostLog.restarted(.notBack(previous: 62873)),
            "host: WallpaperAgent pid 62873 signalled, not back yet"
        ),
        Row("no agent to restart", HostLog.restarted(.notRunning), "host: WallpaperAgent is not running, nothing to restart"),
        Row(
            "the signal failed",
            HostLog.restarted(.signalFailed(pid: 62873, errno: 1)),
            "host: could not signal WallpaperAgent pid 62873, errno 1"
        ),
        Row(
            "a restart refused within ten minutes of the last",
            HostLog.refused(.spiral, .tooSoon(allowedFrom: Date(timeIntervalSince1970: 1_790_000_600))),
            "host: not restarting WallpaperAgent (spiral): restarted less than 10 minutes ago, allowed from 2026-09-21T14:23:20Z"
        ),
        Row(
            "a restart refused until a heartbeat follows the last",
            HostLog.refused(.silence, .awaitingHeartbeat),
            "host: not restarting WallpaperAgent (silence): no heartbeat since the last restart"
        ),
        Row("the metrics probe", HostLog.playbackMetrics(true), "host: playback metrics on"),
        Row("a check", HostLog.checkRequested, "host: check requested"),
    ]

    @Test(arguments: restartsAndStatus)
    func `the restart and status lines read as their parsers expect`(row: Row<String, String>) {
        #expect(row.input == row.expected)
    }
}
