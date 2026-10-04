import Testing
import LivepaperCore

struct StatusLineTests {
    struct Line: Sendable {
        var host: RenderHostStatus
        var showing = 2
        var isPausedAll = false
        var importing: (position: Int, count: Int)?
    }

    static let rows: [Row<Line, StatusLineContent>] = [
        // Every host status.
        Row("live on two displays", Line(host: .live), .idle("Live on 2 displays")),
        Row("live on one display", Line(host: .live, showing: 1), .idle("Live on 1 display")),
        Row("live, with nothing to show", Line(host: .live, showing: 0), .idle("No wallpaper set")),
        Row("stopped under Pause All", Line(host: .stopped, isPausedAll: true), .idle("Paused")),
        Row("stopped otherwise", Line(host: .stopped), .idle("Stopped")),
        Row("Pause All: the host stays live, every display paused in place", Line(host: .live, isPausedAll: true), .idle("Paused")),
        Row(
            "Pause All leaves the host's own trouble on the line",
            Line(host: .recovering(.flush), isPausedAll: true),
            .working("Recovering the wallpaper")
        ),
        Row("connecting", Line(host: .connecting), .working("Connecting to the wallpaper service")),
        Row("not selected, short for the pane's button beside it", Line(host: .notSelected), .idle("Livepaper is not your wallpaper")),
        Row("unavailable", Line(host: .unavailable), .idle("Not available on this version of macOS")),
        Row("recovering by flushing", Line(host: .recovering(.flush)), .working("Recovering the wallpaper")),
        Row("recovering by rebuilding the surface", Line(host: .recovering(.rebuildSurface)), .working("Recovering the wallpaper")),
        Row("recovering by rebuilding the pipeline", Line(host: .recovering(.rebuildPipeline)), .working("Recovering the wallpaper")),
        Row("waiting on a restarted service", Line(host: .recovering(.restartAgent)), .serviceNotResponding),

        // An import takes the line.
        Row("importing one of several", Line(host: .live, importing: (2, 5)), .working("Importing 2 of 5")),
        Row("importing one alone", Line(host: .live, importing: (1, 1)), .working("Importing")),
        Row("an import before connecting", Line(host: .connecting, importing: (1, 3)), .working("Importing 1 of 3")),
        Row("an import before not selected", Line(host: .notSelected, importing: (1, 3)), .working("Importing 1 of 3")),
        Row("an import during Pause All", Line(host: .live, isPausedAll: true, importing: (1, 3)), .working("Importing 1 of 3")),
        Row("a service not responding before an import", Line(host: .recovering(.restartAgent), importing: (1, 3)), .serviceNotResponding),
    ]

    @Test(arguments: rows)
    func `the status line says what the render host and the imports are doing`(row: Row<Line, StatusLineContent>) {
        let line = statusLine(
            host: row.input.host, showing: row.input.showing, isPausedAll: row.input.isPausedAll, importing: row.input.importing
        )

        #expect(line == row.expected)
    }

    struct Restarting: Sendable {
        var host = RenderHostStatus.recovering(.restartAgent)
        var restart: ServiceRestart.Phase
        var importing: (position: Int, count: Int)?
    }

    static let retry = Moment.after(600)

    static let restartRows: [Row<Restarting, StatusLineContent>] = [
        Row("nothing clicked: the service not responding", Restarting(restart: .idle), .serviceNotResponding),
        Row("Restart clicked", Restarting(restart: .restarting), .working("Restarting the wallpaper service")),
        Row(
            "restarted, and waiting for the service to answer",
            Restarting(restart: .waitingForAnswer(until: Moment.after(20), retryFrom: retry)),
            .working("Waiting for the wallpaper service")
        ),
        Row(
            "refused, or no answer: when Restart can next be tried",
            Restarting(restart: .retryFrom(retry)),
            .idle("Restarted recently; try again at 10:10")
        ),
        Row(
            "the restart's words before an import's",
            Restarting(restart: .retryFrom(retry), importing: (1, 2)),
            .idle("Restarted recently; try again at 10:10")
        ),
        Row(
            "the service answered: its status again",
            Restarting(host: .live, restart: .waitingForAnswer(until: Moment.after(20), retryFrom: retry)),
            .idle("Live on 2 displays")
        ),
        Row(
            "a refusal no longer matters once the service answers",
            Restarting(host: .live, restart: .retryFrom(retry)),
            .idle("Live on 2 displays")
        ),
        Row(
            "restarting is said whatever the host reports meanwhile",
            Restarting(host: .live, restart: .restarting),
            .working("Restarting the wallpaper service")
        ),
    ]

    @Test(arguments: restartRows)
    func `the line says Restart is working, waits for an answer, or when it can be tried again`(row: Row<Restarting, StatusLineContent>) {
        let line = statusLine(
            host: row.input.host, showing: 2, isPausedAll: false, importing: row.input.importing, restart: row.input.restart
        ) { date in
            date == Self.retry ? "10:10" : "another time"
        }

        #expect(line == row.expected)
    }

    /// Every line is a sentence without its full stop, as the design system's
    /// "Wallpaper service not responding" is.
    @Test func `no line ends in a full stop`() {
        let lines = Self.rows.map(\.expected) + Self.restartRows.map(\.expected)
        for line in lines {
            switch line {
            case .idle(let words), .working(let words): #expect(!words.hasSuffix("."), "\(words)")
            case .serviceNotResponding: break
            }
        }
    }

    // MARK: The pane beside "not your wallpaper"

    static let paneRows: [Row<Restarting, Bool>] = [
        Row("not selected: the line offers System Settings' Wallpaper pane", Restarting(host: .notSelected, restart: .idle), true),
        Row(
            "not selected, while an import has the line: not offered",
            Restarting(host: .notSelected, restart: .idle, importing: (1, 2)), false
        ),
        Row("not selected, while Restart has the line: not offered", Restarting(host: .notSelected, restart: .restarting), false),
        Row("live: not offered", Restarting(host: .live, restart: .idle), false),
        Row("stopped: not offered", Restarting(host: .stopped, restart: .idle), false),
        Row("not responding: Restart is offered, not the pane", Restarting(restart: .idle), false),
    ]

    @Test(arguments: paneRows)
    func `the pane is offered while the line says Livepaper is not the wallpaper`(row: Row<Restarting, Bool>) {
        let input = row.input
        let offers = statusLineOffersWallpaperPane(host: input.host, importing: input.importing, restart: input.restart)
        let line = statusLine(host: input.host, showing: 2, isPausedAll: false, importing: input.importing, restart: input.restart)

        #expect(offers == row.expected)
        #expect(offers == (line == .idle("Livepaper is not your wallpaper")))
    }
}
