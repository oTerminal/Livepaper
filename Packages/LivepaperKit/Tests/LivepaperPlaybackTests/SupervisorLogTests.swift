import Testing
import LivepaperCore
import LivepaperPlayback

/// Other tools parse these lines (the soak's parser, the release
/// checklist), so a change of wording has to fail here rather than count zero there.
struct SupervisorLogTests {
    static let surface = SupervisorLog.Surface(
        surface: .numbered(1), display: .numbered(2), isPreview: false, wallpaper: .numbered(3), generation: 42
    )
    static let fields = "surface=CCCCCCCC-0000-0000-0000-000000000001 display=DDDDDDDD-0000-0000-0000-000000000002 preview=false "
        + "wallpaper=AAAAAAAA-0000-0000-0000-000000000003 generation=42"
    static let bare = SupervisorLog.Surface(surface: .numbered(1), display: .numbered(2), isPreview: true, wallpaper: nil, generation: nil)
    static let bareFields = "surface=CCCCCCCC-0000-0000-0000-000000000001 display=DDDDDDDD-0000-0000-0000-000000000002 preview=true "
        + "wallpaper=none generation=none"
    static let stopped = RenderState(generation: 42, isStopped: true, displays: [], pauseRules: PauseRules(), conditions: nil)

    static let lines: [Row<String, String>] = [
        // Surface events.
        Row("acquire new", SupervisorLog.acquired(surface, reused: false), "acquire new \(fields)"),
        Row("acquire reused", SupervisorLog.acquired(surface, reused: true), "acquire reused \(fields)"),
        Row("acquire with nothing to show", SupervisorLog.acquired(bare, reused: false), "acquire new \(bareFields)"),
        Row("invalidate", SupervisorLog.invalidated(surface), "invalidate \(fields)"),
        Row(
            "invalidate unknown",
            SupervisorLog.invalidatedUnknown(.numbered(1)),
            "invalidate unknown surface=CCCCCCCC-0000-0000-0000-000000000001"
        ),
        Row("torn down", SupervisorLog.tornDown(surface), "torn down \(fields)"),
        Row("now showing", SupervisorLog.nowShowing(surface, crossfade: true), "now showing \(fields) crossfade=true"),
        Row("holding still", SupervisorLog.holdingStill(surface), "holding still \(fields)"),
        Row("showing nothing", SupervisorLog.showingNothing(bare), "showing nothing \(bareFields)"),
        Row("update", SupervisorLog.updated(surface, mode: .locked), "update \(fields) mode=locked"),

        // Decisions and the render state.
        Row(
            "decision to pause",
            SupervisorLog.decision(display: .numbered(2), target: .playback(.numbered(3), .pause(.desktopCovered)), generation: 42),
            "decision display=DDDDDDDD-0000-0000-0000-000000000002 decision=pause.desktopCovered generation=42"
        ),
        Row(
            "decision to play",
            SupervisorLog.decision(display: .numbered(2), target: .playback(.numbered(3), .play), generation: 42),
            "decision display=DDDDDDDD-0000-0000-0000-000000000002 decision=play generation=42"
        ),
        Row(
            "decision to suspend",
            SupervisorLog.decision(display: .numbered(2), target: .playback(.numbered(3), .suspend(.displayAsleep)), generation: 42),
            "decision display=DDDDDDDD-0000-0000-0000-000000000002 decision=suspend.displayAsleep generation=42"
        ),
        Row(
            "decision to hold the still",
            SupervisorLog.decision(display: .numbered(2), target: .still(.numbered(3)), generation: 42),
            "decision display=DDDDDDDD-0000-0000-0000-000000000002 decision=still generation=42"
        ),
        Row(
            "decision to show nothing",
            SupervisorLog.decision(display: .numbered(2), target: .nothing, generation: nil),
            "decision display=DDDDDDDD-0000-0000-0000-000000000002 decision=nothing generation=none"
        ),
        Row(
            "render state read",
            SupervisorLog.renderState(.read(stopped), kept: nil),
            "render state read generation=42 stopped=true displays=0"
        ),
        Row("render state missing", SupervisorLog.renderState(.missing, kept: nil), "render state missing, showing nothing"),
        Row(
            "render state unreadable",
            SupervisorLog.renderState(.unreadable("malformed"), kept: 41),
            "render state unreadable, keeping generation=41: malformed"
        ),

        // The watchdog.
        Row("check started", SupervisorLog.checkStarted(.wake, judging: 2), "check started reason=wake surfaces=2"),
        Row(
            "check count",
            SupervisorLog.counted(surface, PictureCount(displayed: 3, expected: 60, fed: 57)),
            "check count \(fields) displayed=3 expected=60 fed=57"
        ),
        Row(
            "check count of a scene",
            SupervisorLog.counted(surface, PictureCount(displayed: 60, expected: 60, fed: 60, asked: 60, presented: 6)),
            "check count \(fields) displayed=60 expected=60 fed=60 asked=60 presented=6"
        ),
        Row(
            "check count of a covered scene",
            SupervisorLog.counted(surface, PictureCount(displayed: 0, expected: 60, fed: 0, asked: 0, withheld: true, presented: 0)),
            "check count \(fields) displayed=0 expected=60 fed=0 asked=0 presented=0 withheld"
        ),
        Row("verdict healthy", SupervisorLog.verdict(surface, .healthy, attempt: 0), "check verdict \(fields) verdict=healthy attempt=0"),
        Row(
            "verdict not composited",
            SupervisorLog.verdict(surface, .notComposited, attempt: 1),
            "check verdict \(fields) verdict=notComposited attempt=1"
        ),
        Row(
            "verdict flush",
            SupervisorLog.verdict(surface, .recover(.flush), attempt: 0),
            "check verdict \(fields) verdict=flush attempt=0"
        ),
        Row(
            "verdict rebuild surface",
            SupervisorLog.verdict(surface, .recover(.rebuildSurface), attempt: 1),
            "check verdict \(fields) verdict=rebuildSurface attempt=1"
        ),
        Row(
            "verdict rebuild pipeline",
            SupervisorLog.verdict(surface, .recover(.rebuildPipeline), attempt: 2),
            "check verdict \(fields) verdict=rebuildPipeline attempt=2"
        ),
        Row(
            "verdict restart",
            SupervisorLog.verdict(surface, .requestRestart, attempt: 3),
            "check verdict \(fields) verdict=restartAgent attempt=3"
        ),
        Row(
            "recovery tried",
            SupervisorLog.recoveryTried(surface, level: .rebuildPipeline),
            "recovery tried \(fields) level=rebuildPipeline"
        ),
        Row("restart requested", SupervisorLog.restartRequested(surface), "restart requested \(fields)"),
        Row("restart request cleared", SupervisorLog.restartRequestCleared, "restart request cleared"),
        Row("recover requested", SupervisorLog.recoverRequested(.flush, stalled: 1), "recover requested level=flush stalled=1"),
    ]

    @Test(arguments: lines)
    func `words each line once and for all`(row: Row<String, String>) {
        #expect(row.input == row.expected)
    }
}
