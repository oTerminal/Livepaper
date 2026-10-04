import Foundation
import LivepaperCore
import LivepaperPlayback
import LivepaperSoak
import LivepaperSystem
import Testing

/// Stalls into episodes, by the soak's definitions: an episode opens at a
/// stall and closes at the next `.healthy` for that surface, or `.live` for the host.
struct EpisodesTests {
    static let one = SupervisorLog.Surface(
        surface: .numbered(1), display: .numbered(2), isPreview: false, wallpaper: .numbered(3), generation: 42
    )
    static let oneTag = SurfaceTag(
        surface: Named.surface(1), display: Named.display(2), isPreview: false, wallpaper: Named.wallpaper(3), generation: 42
    )
    static let two = SupervisorLog.Surface(
        surface: .numbered(5), display: .numbered(6), isPreview: false, wallpaper: .numbered(3), generation: 42
    )
    static let twoTag = SurfaceTag(
        surface: Named.surface(5), display: Named.display(6), isPreview: false, wallpaper: Named.wallpaper(3), generation: 42
    )

    static func playing(_ display: Int, at seconds: TimeInterval = 0) -> LogLine {
        Logged.supervisor(
            SupervisorLog.decision(display: .numbered(display), target: .playback(.numbered(3), .play), generation: 42), at: .soak(seconds)
        )
    }

    static func verdict(_ surface: SupervisorLog.Surface, _ step: WatchdogStep, attempt: Int, at seconds: TimeInterval) -> LogLine {
        Logged.supervisor(SupervisorLog.verdict(surface, step, attempt: attempt), at: .soak(seconds))
    }

    static func episodes(_ lines: [LogLine], markers: [SoakMarker] = []) -> Episodes {
        Episodes(log: SoakLog(lines: lines), markers: markers)
    }

    @Test
    func `a stall that the next check finds healthy is recovered at its level, charged to the wake before it`() {
        let episodes = Self.episodes([
            Self.playing(2),
            Logged.extensionLine("extension: woke source=system", at: .soak(100)),
            Self.verdict(Self.one, .recover(.flush), attempt: 0, at: 102),
            Self.verdict(Self.one, .healthy, attempt: 1, at: 104),
        ])

        #expect(episodes.all == [
            Episode(
                subject: .surface(Self.oneTag), opened: .soak(102), closed: .soak(104), level: .flush,
                outcome: .recovered, trigger: Trigger(kind: .wake, time: .soak(100))
            ),
        ])
    }

    @Test
    func `an episode's level is the highest rung the ladder reached`() {
        let episodes = Self.episodes([
            Self.playing(2),
            Self.verdict(Self.one, .recover(.flush), attempt: 0, at: 10),
            Self.verdict(Self.one, .notComposited, attempt: 1, at: 12),
            Self.verdict(Self.one, .recover(.rebuildSurface), attempt: 1, at: 14),
            Self.verdict(Self.one, .recover(.rebuildPipeline), attempt: 2, at: 16),
            Self.verdict(Self.one, .healthy, attempt: 3, at: 18),
        ])

        #expect(episodes.all.map(\.level) == [.rebuildPipeline])
        #expect(episodes.all.map(\.closed) == [.soak(18)])
        #expect(episodes.all.map(\.outcome) == [.recovered])
    }

    static let unrecovered: [Row<[LogLine], Episode.Outcome>] = [
        Row(
            "reaching the ladder's top, though healthy after",
            [
                playing(2), verdict(one, .recover(.rebuildPipeline), attempt: 2, at: 10),
                verdict(one, .requestRestart, attempt: 3, at: 12), verdict(one, .healthy, attempt: 0, at: 40),
            ],
            .unrecovered(.reachedRestart)
        ),
        Row(
            "the extension asking for the restart",
            [
                playing(2), verdict(one, .recover(.flush), attempt: 0, at: 10),
                Logged.supervisor(SupervisorLog.restartRequested(one), at: .soak(12)), verdict(one, .healthy, attempt: 0, at: 40),
            ],
            .unrecovered(.reachedRestart)
        ),
        Row(
            "its surface torn down before a healthy check",
            [playing(2), verdict(one, .recover(.flush), attempt: 0, at: 10), Logged.supervisor(SupervisorLog.tornDown(one), at: .soak(11))],
            .unrecovered(.neverClosed)
        ),
        Row(
            "its surface invalidated before a healthy check",
            [
                playing(2), verdict(one, .recover(.flush), attempt: 0, at: 10),
                Logged.supervisor(SupervisorLog.invalidated(one), at: .soak(11)),
            ],
            .unrecovered(.neverClosed)
        ),
        Row(
            "the extension starting again before a healthy check",
            [
                playing(2), verdict(one, .recover(.flush), attempt: 0, at: 10),
                Logged.extensionLine("extension: launched pid=900 version=0.1.0 build=1 bundle=/x", at: .soak(11)),
                verdict(one, .healthy, attempt: 0, at: 20),
            ],
            .unrecovered(.neverClosed)
        ),
        Row("still open when the soak ended", [playing(2), verdict(one, .recover(.flush), attempt: 0, at: 10)], .unrecovered(.openAtEnd)),
    ]

    @Test(arguments: unrecovered)
    func `an episode is unrecovered`(row: Row<[LogLine], Episode.Outcome>) {
        #expect(Self.episodes(row.input).all.map(\.outcome) == [row.expected])
    }

    @Test
    func `a verdict on a covered display is no stall, and is listed apart`() {
        let covered = Logged.supervisor(
            SupervisorLog.decision(display: .numbered(2), target: .playback(.numbered(3), .pause(.desktopCovered)), generation: 42),
            at: .soak(5)
        )
        let judged = Self.verdict(Self.one, .recover(.flush), attempt: 0, at: 10)

        let episodes = Self.episodes([Self.playing(2), covered, judged, Self.playing(2, at: 20)])

        #expect(episodes.all.isEmpty)
        #expect(episodes.judgedWhileCovered.map(\.line) == [judged])
    }

    @Test
    func `on the lock screen covering does not count`() {
        let covered = Logged.supervisor(
            SupervisorLog.decision(display: .numbered(2), target: .playback(.numbered(3), .pause(.desktopCovered)), generation: 42),
            at: .soak(5)
        )
        let locked = Logged.supervisor(SupervisorLog.updated(Self.one, mode: .locked), at: .soak(6))

        let episodes = Self.episodes([Self.playing(2), covered, locked, Self.verdict(Self.one, .recover(.flush), attempt: 0, at: 10)])

        #expect(episodes.all.map(\.opened) == [.soak(10)])
        #expect(episodes.judgedWhileCovered.isEmpty)
    }

    @Test
    func `two surfaces stalling at one wake are two episodes`() {
        let episodes = Self.episodes([
            Self.playing(2),
            Self.playing(6),
            Logged.extensionLine("extension: woke source=system", at: .soak(100)),
            Self.verdict(Self.one, .recover(.flush), attempt: 0, at: 102),
            Self.verdict(Self.two, .recover(.flush), attempt: 0, at: 102),
            Self.verdict(Self.two, .healthy, attempt: 1, at: 104),
        ])

        #expect(episodes.all.map(\.subject) == [.surface(Self.oneTag), .surface(Self.twoTag)])
        #expect(episodes.all.map(\.outcome) == [.unrecovered(.openAtEnd), .recovered])
    }

    static func host(_ status: RenderHostStatus, at seconds: TimeInterval) -> LogLine {
        Logged.host(HostLog.status(status), at: .soak(seconds))
    }

    @Test
    func `the host leaving live for recovering opens an episode that live closes`() {
        let episodes = Self.episodes([
            Self.host(.connecting, at: 0),
            Self.host(.live, at: 1),
            Self.host(.recovering(.flush), at: 100),
            Self.host(.recovering(.rebuildSurface), at: 110),
            Self.host(.live, at: 115),
        ])

        #expect(episodes.all == [
            Episode(subject: .host, opened: .soak(100), closed: .soak(115), level: .rebuildSurface, outcome: .recovered, trigger: nil),
        ])
    }

    static let hostOutcomes: [Row<[LogLine], [Episode.Outcome]>] = [
        Row(
            "recovering before it was ever live is no stall",
            [host(.connecting, at: 0), host(.recovering(.flush), at: 20), host(.live, at: 30)],
            []
        ),
        Row(
            "reaching the restart",
            [host(.live, at: 0), host(.recovering(.flush), at: 20), host(.recovering(.restartAgent), at: 60), host(.live, at: 70)],
            [.unrecovered(.reachedRestart)]
        ),
        Row(
            "never live again",
            [host(.live, at: 0), host(.recovering(.flush), at: 20), host(.stopped, at: 30)],
            [.unrecovered(.openAtEnd)]
        ),
        Row(
            "stopped between, then live",
            [host(.live, at: 0), host(.recovering(.flush), at: 20), host(.stopped, at: 30), host(.live, at: 40)],
            [.recovered]
        ),
    ]

    @Test(arguments: hostOutcomes)
    func `the host's episodes`(row: Row<[LogLine], [Episode.Outcome]>) {
        #expect(Self.episodes(row.input).all.map(\.outcome) == row.expected)
    }
}

/// The trigger an episode is charged to: the last one at or before it opened.
struct TriggerTests {
    struct Before: Sendable {
        var lines: [LogLine]
        var markers: [SoakMarker] = []
    }

    static let woke = Logged.extensionLine("extension: woke source=system", at: .soak(100))
    static let displaysWoke = Logged.extensionLine("extension: woke source=displays", at: .soak(100))
    static let replugged = [
        Logged.supervisor(SupervisorLog.invalidated(EpisodesTests.one), at: .soak(90)),
        Logged.supervisor(SupervisorLog.acquired(SupervisorLog.Surface(
            surface: .numbered(7), display: .numbered(2), isPreview: false, wallpaper: .numbered(3), generation: 42
        ), reused: false), at: .soak(100)),
    ]

    static func at(_ kind: TriggerKind, _ seconds: TimeInterval = 100, display: Int? = nil) -> Trigger {
        Trigger(kind: kind, time: .soak(seconds), display: display.map(Named.display))
    }

    static let triggers: [Row<Before, Trigger?>] = [
        Row("nothing before it", Before(lines: []), nil),
        Row("the Mac woke", Before(lines: [woke]), at(.wake)),
        Row("the Mac woke after a marked lid", Before(lines: [woke], markers: [SoakMarker(time: .soak(50), kind: .lid)]), at(.lid)),
        Row(
            "the Mac woke after a lid, then a scripted sleep",
            Before(lines: [woke], markers: [SoakMarker(time: .soak(40), kind: .lid), SoakMarker(time: .soak(50), kind: .sleep)]),
            at(.wake)
        ),
        Row("the displays woke", Before(lines: [displaysWoke]), at(.displayWake)),
        Row(
            "the displays woke after a marked lid: awake on the external",
            Before(lines: [displaysWoke], markers: [SoakMarker(time: .soak(50), kind: .lid)]),
            at(.lidOnExternal)
        ),
        Row("unlocked", Before(lines: [Logged.extensionLine("extension: unlocked", at: .soak(100))]), at(.unlock)),
        Row(
            "a tick rotated a display",
            Before(lines: [Logged.rotation(RotationLog.rotated(.tick, [.numbered(2)]), at: .soak(100))]),
            at(.rotation)
        ),
        Row("a tick rotated nothing", Before(lines: [Logged.rotation(RotationLog.rotated(.tick, []), at: .soak(100))]), nil),
        Row(
            "a wake's rotation stays the wake's",
            Before(lines: [woke, Logged.rotation(RotationLog.rotated(.wake, [.numbered(2)]), at: .soak(101))]),
            at(.wake)
        ),
        Row("a display came back as a new surface", Before(lines: replugged), at(.replug, display: 2)),
        Row(
            "a display came back after a marked lid",
            Before(lines: replugged, markers: [SoakMarker(time: .soak(80), kind: .lid)]),
            at(.lidOnExternal, display: 2)
        ),
        Row(
            "a display changed mode",
            Before(lines: [
                Logged.extensionLine(
                    "extension: display reconfigured display=\(Named.display(2)) from=1920x1080@1.0 to=1280x1024@1.0", at: .soak(100)
                ),
            ]),
            at(.replug, display: 2)
        ),
        Row(
            "a display's first surface",
            Before(lines: [Logged.supervisor(SupervisorLog.acquired(EpisodesTests.one, reused: false), at: .soak(100))]),
            nil
        ),
        Row(
            "the extension started again, and its surfaces with it",
            Before(lines: [Logged.extensionLine("extension: launched pid=900 version=0.1.0 build=1 bundle=/x", at: .soak(95))] + replugged),
            at(.restart, 95)
        ),
        Row(
            "a new agent, and the surfaces it acquired again",
            Before(lines: [
                Logged.bridge("bridge: connection from pid 668 accepted", at: .soak(10)),
                Logged.bridge("bridge: connection from pid 902 accepted", at: .soak(95)),
            ] + replugged),
            at(.restart, 95)
        ),
        Row(
            "the same agent connecting again",
            Before(lines: [
                Logged.bridge("bridge: connection from pid 668 accepted", at: .soak(10)),
                Logged.bridge("bridge: connection from pid 668 accepted", at: .soak(100)),
            ]),
            nil
        ),
        Row(
            "a marked fast user switch",
            Before(lines: [], markers: [SoakMarker(time: .soak(100), kind: .fastUserSwitch)]),
            at(.userSwitch)
        ),
        Row("a marked recovery drill", Before(lines: [], markers: [SoakMarker(time: .soak(100), kind: .drill)]), at(.drill)),
        // SystemEvents: "Both wakes may come for one lid cycle".
        Row(
            "the Mac's wake and its displays' are one wake",
            Before(lines: [woke, Logged.extensionLine("extension: woke source=displays", at: .soak(101))]),
            at(.wake)
        ),
        Row(
            "the displays' wake and then the Mac's are one wake",
            Before(lines: [displaysWoke, Logged.extensionLine("extension: woke source=system", at: .soak(101))]),
            at(.wake)
        ),
        Row(
            "the displays' wake and then the Mac's after a marked lid are a lid slept through",
            Before(
                lines: [displaysWoke, Logged.extensionLine("extension: woke source=system", at: .soak(101))],
                markers: [SoakMarker(time: .soak(50), kind: .lid)]
            ),
            at(.lid)
        ),
    ]

    @Test(arguments: triggers)
    func `an episode is charged to the trigger before it`(row: Row<Before, Trigger?>) {
        let stall = EpisodesTests.verdict(EpisodesTests.one, .recover(.flush), attempt: 0, at: 500)
        let episodes = EpisodesTests.episodes([EpisodesTests.playing(2)] + row.input.lines + [stall], markers: row.input.markers)

        #expect(episodes.all.map(\.trigger) == [row.expected])
    }

    @Test
    func `one wake's two lines are one event`() {
        let episodes = EpisodesTests.episodes([Self.woke, Logged.extensionLine("extension: woke source=displays", at: .soak(101))])

        #expect(episodes.triggers == [Self.at(.wake)])
    }

    @Test
    func `a replug's lines within 10 s are one event`() {
        let episodes = EpisodesTests.episodes(Self.replugged + [
            Logged.extensionLine("extension: display reconfigured display=\(Named.display(2)) from=none to=1920x1080@1.0", at: .soak(101)),
            Logged.extensionLine(
                "extension: display reconfigured display=\(Named.display(2)) from=1920x1080@1.0 to=1280x1024@1.0", at: .soak(200)
            ),
        ])

        #expect(episodes.triggers == [Self.at(.replug, display: 2), Self.at(.replug, 200, display: 2)])
    }
}
