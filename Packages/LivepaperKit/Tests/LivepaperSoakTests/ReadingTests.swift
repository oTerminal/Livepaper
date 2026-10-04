import Foundation
import LivepaperCore
import LivepaperPlayback
import LivepaperSoak
import LivepaperSystem
import Testing
@testable import WallpaperAgentBridge

/// Each line the soak counts, built with the product's own wording where the
/// package has it (`SupervisorLog`, `HostLog`, `RotationLog`, `PlaybackMetrics`),
/// and pinned by hand where only the extension has
/// it (`ExtensionLog`, `BridgeLog`), so a rename fails here instead of counting zero.
struct SupervisorReadingTests {
    static let fields = SupervisorLog.Surface(
        surface: .numbered(1), display: .numbered(2), isPreview: false, wallpaper: .numbered(3), generation: 42
    )
    static let tag = SurfaceTag(
        surface: Named.surface(1), display: Named.display(2), isPreview: false, wallpaper: Named.wallpaper(3), generation: 42
    )
    static let bareFields = SupervisorLog.Surface(
        surface: .numbered(1), display: .numbered(2), isPreview: true, wallpaper: nil, generation: nil
    )
    static let bareTag = SurfaceTag(
        surface: Named.surface(1), display: Named.display(2), isPreview: true, wallpaper: nil, generation: nil
    )

    static let supervisor: [Row<LogLine, Reading>] = [
        Row("acquire new", Logged.supervisor(SupervisorLog.acquired(fields, reused: false)), .event(.acquired(tag, reused: false))),
        Row("acquire reused", Logged.supervisor(SupervisorLog.acquired(fields, reused: true)), .event(.acquired(tag, reused: true))),
        Row(
            "acquire of a preview with nothing to show",
            Logged.supervisor(SupervisorLog.acquired(bareFields, reused: false)),
            .event(.acquired(bareTag, reused: false))
        ),
        Row("invalidate", Logged.supervisor(SupervisorLog.invalidated(fields)), .event(.invalidated(tag))),
        Row("invalidate unknown", Logged.supervisor(SupervisorLog.invalidatedUnknown(.numbered(1))), .known),
        Row("torn down", Logged.supervisor(SupervisorLog.tornDown(fields)), .event(.tornDown(tag))),
        Row("now showing", Logged.supervisor(SupervisorLog.nowShowing(fields, crossfade: true)), .event(.shows(tag, .playing))),
        Row("holding still", Logged.supervisor(SupervisorLog.holdingStill(fields)), .event(.shows(tag, .still))),
        Row("showing nothing", Logged.supervisor(SupervisorLog.showingNothing(bareFields)), .event(.shows(bareTag, .nothing))),
        Row("update to locked", Logged.supervisor(SupervisorLog.updated(fields, mode: .locked)), .event(.mode(tag, isLocked: true))),
        Row("update to desktop", Logged.supervisor(SupervisorLog.updated(fields, mode: .desktop)), .event(.mode(tag, isLocked: false))),
        Row(
            "decision to pause, covered",
            Logged.supervisor(SupervisorLog.decision(
                display: .numbered(2), target: .playback(.numbered(3), .pause(.desktopCovered)), generation: 42
            )),
            .event(.decision(display: Named.display(2), .pause("desktopCovered")))
        ),
        Row(
            "decision to suspend, asleep",
            Logged.supervisor(SupervisorLog.decision(
                display: .numbered(2), target: .playback(.numbered(3), .suspend(.displayAsleep)), generation: 42
            )),
            .event(.decision(display: Named.display(2), .suspend("displayAsleep")))
        ),
        Row(
            "decision to play",
            Logged.supervisor(SupervisorLog.decision(display: .numbered(2), target: .playback(.numbered(3), .play), generation: 42)),
            .event(.decision(display: Named.display(2), .play))
        ),
        Row(
            "decision to hold the still",
            Logged.supervisor(SupervisorLog.decision(display: .numbered(2), target: .still(.numbered(3)), generation: 42)),
            .event(.decision(display: Named.display(2), .still))
        ),
        Row(
            "decision to show nothing",
            Logged.supervisor(SupervisorLog.decision(display: .numbered(2), target: .nothing, generation: nil)),
            .event(.decision(display: Named.display(2), .nothing))
        ),
        Row(
            "render state read",
            Logged.supervisor(SupervisorLog.renderState(
                .read(RenderState(generation: 42, isStopped: false, displays: [], pauseRules: PauseRules(), conditions: nil)), kept: nil
            )),
            .known
        ),
        Row("render state missing", Logged.supervisor(SupervisorLog.renderState(.missing, kept: nil)), .known),
        Row("render state unreadable", Logged.supervisor(SupervisorLog.renderState(.unreadable("cut short"), kept: 41)), .known),
        Row(
            "check started after a wake",
            Logged.supervisor(SupervisorLog.checkStarted(.wake, judging: 2)),
            .event(.checkStarted(reason: "wake", surfaces: 2))
        ),
        Row(
            "check count of a video",
            Logged.supervisor(SupervisorLog.counted(fields, PictureCount(displayed: 119, expected: 120, fed: 61))),
            .event(.counted(tag, PictureTally(displayed: 119, expected: 120, fed: 61)))
        ),
        Row(
            "check count of a scene whose link was withheld",
            Logged.supervisor(SupervisorLog.counted(
                fields, PictureCount(displayed: 2, expected: 60, fed: 0, asked: 3, withheld: true, presented: 2)
            )),
            .event(.counted(tag, PictureTally(displayed: 2, expected: 60, fed: 0, asked: 3, presented: 2, withheld: true)))
        ),
        Row(
            "verdict healthy",
            Logged.supervisor(SupervisorLog.verdict(fields, .healthy, attempt: 0)),
            .event(.verdict(tag, .healthy, attempt: 0))
        ),
        Row(
            "verdict not composited",
            Logged.supervisor(SupervisorLog.verdict(fields, .notComposited, attempt: 0)),
            .event(.verdict(tag, .notComposited, attempt: 0))
        ),
        Row(
            "verdict flush",
            Logged.supervisor(SupervisorLog.verdict(fields, .recover(.flush), attempt: 0)),
            .event(.verdict(tag, .recover(.flush), attempt: 0))
        ),
        Row(
            "verdict rebuild the pipeline",
            Logged.supervisor(SupervisorLog.verdict(fields, .recover(.rebuildPipeline), attempt: 2)),
            .event(.verdict(tag, .recover(.rebuildPipeline), attempt: 2))
        ),
        Row(
            "verdict at the ladder's top",
            Logged.supervisor(SupervisorLog.verdict(fields, .requestRestart, attempt: 3)),
            .event(.verdict(tag, .recover(.restartAgent), attempt: 3))
        ),
        Row(
            "recovery tried",
            Logged.supervisor(SupervisorLog.recoveryTried(fields, level: .rebuildSurface)),
            .event(.recoveryTried(tag, .rebuildSurface))
        ),
        Row("restart requested", Logged.supervisor(SupervisorLog.restartRequested(fields)), .event(.restartRequested(tag))),
        Row("restart request cleared", Logged.supervisor(SupervisorLog.restartRequestCleared), .known),
        Row("the app's recover", Logged.supervisor(SupervisorLog.recoverRequested(.flush, stalled: 1)), .known),
    ]

    @Test(arguments: supervisor)
    func `reads the supervisor's lines`(row: Row<LogLine, Reading>) {
        #expect(Reading(row.input) == row.expected)
    }
}

/// `ExtensionLog` lives in the extension, out of this package's reach: its rows
/// are its wording, word for word. The bridge's are built with `BridgeLog` and
/// `BridgeSelfCheck`, which the package has.
struct ExtensionReadingTests {
    static let extensionLines: [Row<LogLine, Reading>] = [
        Row(
            "launched",
            Logged.extensionLine(
                "extension: launched pid=711 version=0.1.0 build=1 "
                    + "bundle=/Applications/Livepaper.app/Contents/Extensions/WallpaperExtension.appex"
            ),
            .event(.extensionLaunched(pid: 711))
        ),
        Row("woke, the Mac", Logged.extensionLine("extension: woke source=system"), .event(.woke(.system))),
        Row("woke, the displays", Logged.extensionLine("extension: woke source=displays"), .event(.woke(.displays))),
        Row("unlocked", Logged.extensionLine("extension: unlocked"), .event(.unlocked)),
        Row(
            "display reconfigured",
            Logged.extensionLine("extension: display reconfigured display=\(Named.display(2)) from=1920x1080@1.0 to=1280x1024@1.0"),
            .event(.displayReconfigured(display: Named.display(2)))
        ),
        Row(
            "display reconfigured, first seen",
            Logged.extensionLine("extension: display reconfigured display=\(Named.display(2)) from=none to=1920x1080@1.0"),
            .event(.displayReconfigured(display: Named.display(2)))
        ),
        Row(
            "context made",
            Logged.extensionLine(
                "extension: context made surface=\(Named.surface(1)) context=3600226096 display=\(Named.display(2)) preview=false"
            ),
            .known
        ),
        Row("recover received", Logged.extensionLine("extension: recover received level=flush"), .known),
        Row("check received", Logged.extensionLine("extension: check received"), .known),
        Row("metrics probe", Logged.extensionLine("extension: playback metrics probe on"), .known),
        Row("a woke line reworded", Logged.extensionLine("extension: woken source=system"), .unparsed),
        Row(
            "self-check, all present",
            Logged.bridge(BridgeSelfCheck(missing: []).logLine),
            .event(.selfCheck(isUsable: true, missing: []))
        ),
        Row(
            "self-check, usable",
            Logged.bridge(BridgeSelfCheck(missing: [.videoCompositingSelector]).logLine),
            .event(.selfCheck(isUsable: true, missing: ["-[AVSampleBufferDisplayLayer _setDisallowsVideoLayerDisplayCompositing:]"]))
        ),
        Row(
            "self-check, failed",
            Logged.bridge(BridgeSelfCheck(missing: [.framework, .remoteContextFactory]).logLine),
            .event(.selfCheck(isUsable: false, missing: ["WallpaperExtensionKit", "+[CAContext remoteContextWithOptions:]"]))
        ),
        Row("spiral", Logged.bridge(BridgeLog.spiral(emptyInARow: 5)), .event(.spiral(emptyConnections: 5))),
        Row("connection accepted", Logged.bridge(BridgeLog.accepted(pid: 668)), .event(.agentConnected(pid: 668))),
        Row("connection served", Logged.bridge(BridgeLog.ended(pid: 668, served: true, emptyInARow: 0)), .known),
        Row("connection empty", Logged.bridge(BridgeLog.ended(pid: 668, served: false, emptyInARow: 2)), .known),
        Row(
            "the agent's acquire",
            Logged.bridge(
                "bridge: acquire surface \(Named.surface(1)) display 1 size 1800x1169@2.0 preview false "
                    + "presentationMode=default activityState=active"
            ),
            .known
        ),
    ]

    @Test(arguments: extensionLines)
    func `reads the extension's and the bridge's lines`(row: Row<LogLine, Reading>) {
        #expect(Reading(row.input) == row.expected)
    }

    /// The categories are the `Logger`s' in `ExtensionLog.swift` and `BridgeLog.swift`, out of reach as strings.
    @MainActor @Test
    func `reads the subsystems the product logs under`() {
        #expect(Reading.extensionSubsystem == WallpaperExtensionIdentity.logSubsystem)
        #expect(Reading.appSubsystem == LivepaperSystem.logSubsystem)
        #expect(Logged.appSubsystem == LivepaperSystem.logSubsystem)
    }
}

struct AppReadingTests {
    static let appLines: [Row<LogLine, Reading>] = [
        Row("status live", Logged.host(HostLog.status(.live)), .event(.hostStatus(.live))),
        Row("status connecting", Logged.host(HostLog.status(.connecting)), .event(.hostStatus(.connecting))),
        Row("status stopped", Logged.host(HostLog.status(.stopped)), .event(.hostStatus(.stopped))),
        Row("status not selected", Logged.host(HostLog.status(.notSelected)), .event(.hostStatus(.notSelected))),
        Row("status unavailable", Logged.host(HostLog.status(.unavailable)), .event(.hostStatus(.unavailable))),
        Row("status recovering, flush", Logged.host(HostLog.status(.recovering(.flush))), .event(.hostStatus(.recovering(.flush)))),
        Row(
            "status recovering, restart",
            Logged.host(HostLog.status(.recovering(.restartAgent))),
            .event(.hostStatus(.recovering(.restartAgent)))
        ),
        Row("restarting the agent", Logged.host(HostLog.restarting(.watchdog)), .event(.agentRestarting(reason: "watchdog"))),
        Row(
            "the agent restarted",
            Logged.host(HostLog.restarted(.restarted(previous: 668, current: 902))),
            .event(.agentRestarted(previous: 668, current: 902))
        ),
        Row("the agent not back", Logged.host(HostLog.restarted(.notBack(previous: 668))), .known),
        Row("no agent to restart", Logged.host(HostLog.restarted(.notRunning)), .known),
        Row("signal failed", Logged.host(HostLog.restarted(.signalFailed(pid: 668, errno: 1))), .known),
        Row("restart refused", Logged.host(HostLog.refused(.spiral, .awaitingHeartbeat)), .known),
        Row("restart too soon", Logged.host(HostLog.refused(.user, .tooSoon(allowedFrom: .soak(600)))), .known),
        Row("activated", Logged.host(HostLog.activated), .known),
        Row("silence", Logged.host(HostLog.silence(.flush)), .known),
        Row("skipped", Logged.host(HostLog.skipped(.flush)), .known),
        Row("the app's recover", Logged.host(HostLog.recover(.rebuildSurface)), .known),
        Row(
            "render state written",
            Logged.host(HostLog.renderStateWritten(RenderState(
                generation: 7, isStopped: false, displays: [], pauseRules: PauseRules(), conditions: nil
            ))),
            .known
        ),
        Row("nothing to stop", Logged.host(HostLog.nothingToStop), .known),
        Row("metrics on", Logged.host(HostLog.playbackMetrics(true)), .known),
        Row("check requested", Logged.host(HostLog.checkRequested), .known),
        Row("a status line reworded", Logged.host("host: state live"), .unparsed),
        Row(
            "a tick rotated one display",
            Logged.rotation(RotationLog.rotated(.tick, [.numbered(2)])),
            .event(.rotated(.tick, displays: [Named.display(2)]))
        ),
        Row(
            "a wake rotated two",
            Logged.rotation(RotationLog.rotated(.wake, [.numbered(2), .numbered(4)])),
            .event(.rotated(.wake, displays: [Named.display(2), Named.display(4)]))
        ),
        Row("a tick rotated nothing", Logged.rotation(RotationLog.rotated(.tick, [])), .event(.rotated(.tick, displays: []))),
        Row("session started", Logged.rotation(RotationLog.login(sessionStart: .soakStart, rotated: [])), .known),
        Row("counting", Logged.rotation(RotationLog.counting([.numbered(2)], from: .soakStart)), .known),
        Row("next tick", Logged.rotation(RotationLog.nextTick(.soak(300))), .known),
        Row("no tick due", Logged.rotation(RotationLog.nextTick(nil)), .known),
        Row("a tick moved nothing", Logged.rotation(RotationLog.tickMovedNothing), .known),
        Row(
            "conditions",
            Logged.sensing(SensingLog.conditions(SensedConditions(sensedAt: .soakStart, coveredDisplays: [.numbered(2)]))),
            .known
        ),
    ]

    @Test(arguments: appLines)
    func `reads the app's lines`(row: Row<LogLine, Reading>) {
        #expect(Reading(row.input) == row.expected)
    }

    @Test
    func `ignores other subsystems and the app's other categories`() {
        #expect(
            Reading(Logged.line("com.apple.wallpaper", "agent", "acquire new", time: .soakStart, process: "WallpaperAgent")) == .ignored
        )
        #expect(Reading(Logged.line("app.livepaper.tests", "supervisor", "check verdict", time: .soakStart, process: "xctest")) == .ignored)
        #expect(Reading(Logged.line(Logged.appSubsystem, "workshop", "anything", time: .soakStart, process: "Livepaper")) == .ignored)
    }
}

struct EngineReadingTests {
    static let metrics = PlaybackMetrics(
        video: "\(WallpaperID.numbered(3))/wallpaper.mov", loops: 200, seamsWatched: 199,
        largestSeamStep: 1, largestInLoopStep: 1, largestPresentedGap: 1.56, largestPresentedGapAtSeam: 1.11,
        gapsOverLimitAtSeams: 0, gapsOverLimitElsewhere: 1, droppedFrames: 2, totalFrames: 43_391, smallestSeamLead: 1.19,
        flushes: 0, failures: 0, markerBuffersSkipped: 800, nextReaderMisses: 0
    )
    static let metricsLine = MetricsLine(
        surface: Named.surface(1), folder: Named.wallpaper(3), file: "wallpaper.mov", loops: 200, seamsWatched: 199,
        largestSeamStep: 1, largestInLoopStep: 1, largestPresentedGap: 1.56, largestPresentedGapAtSeam: 1.11,
        gapsOverLimitAtSeams: 0, gapsOverLimitElsewhere: 1, droppedFrames: 2, totalFrames: 43_391, smallestSeamLead: 1.19,
        flushes: 0, failures: 0, markersSkipped: 800, nextReaderMisses: 0
    )

    static let engineLines: [Row<LogLine, Reading>] = [
        Row("the metrics line", Logged.surface(metrics.logLine(for: .surface(.numbered(1)))), .event(.metrics(metricsLine))),
        Row(
            "the metrics line before the probe saw a picture",
            Logged.surface(
                PlaybackMetrics(video: "\(WallpaperID.numbered(3))/wallpaper.mov", loops: 20).logLine(for: .surface(.numbered(1)))
            ),
            .event(.metrics(MetricsLine(
                surface: Named.surface(1), folder: Named.wallpaper(3), file: "wallpaper.mov", loops: 20, seamsWatched: 0
            )))
        ),
        Row(
            "the metrics line with its last field renamed",
            Logged.surface(
                metrics.logLine(for: .surface(.numbered(1))).replacingOccurrences(of: "next-reader misses", with: "late readers")
            ),
            .unparsed
        ),
        Row(
            "an engine line",
            Logged.surface(
                "engine: renderer asked for a flush on \(Named.wallpaper(3))/wallpaper.mov, starting again from a fresh reader"
            ),
            .known
        ),
        Row(
            "a layers line",
            Logged.surface("layers: surface \(Named.surface(1)) had no picture of x/wallpaper.mov after 1 s, going ahead"),
            .known
        ),
        Row("a scene line", Logged.surface("scene: surface \(Named.surface(1)) drawing at 30 fps from 0.00 s"), .known),
    ]

    @Test(arguments: engineLines)
    func `reads the engine's lines`(row: Row<LogLine, Reading>) {
        #expect(Reading(row.input) == row.expected)
    }
}
