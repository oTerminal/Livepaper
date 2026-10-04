import Foundation
import LivepaperSoak
import Testing

/// A whole `log show` export, as `soak.sh` appends it hour by hour.
struct SoakLogTests {
    static func fixture() throws -> String {
        let url = try #require(Bundle.module.url(forResource: "soak", withExtension: "log", subdirectory: "Fixtures"))
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test
    func `reads every line of the real fixture, ignoring launchd's`() throws {
        let log = SoakLog(text: try Self.fixture())

        #expect(log.unparsed.isEmpty)
        #expect(log.ignoredCount == 1)
        #expect(log.lines.count == 10)
        let events = log.entries.map(\.event)
        #expect(events.first == .extensionLaunched(pid: 711))
        #expect(events.contains(.selfCheck(isUsable: true, missing: [])))
        #expect(events.contains(.agentConnected(pid: 668)))
        #expect(events.contains(.decision(display: "37D8832A-2D66-02CA-B9F7-8F30A301B230", .still)))
        let surface = SurfaceTag(
            surface: "EAAF840D-2B58-4684-A2F4-24AF8036B9E8", display: "37D8832A-2D66-02CA-B9F7-8F30A301B230", isPreview: false,
            wallpaper: "8DC8CFEF-ADA1-440B-8462-94642B727C49", generation: 2293
        )
        #expect(events.contains(.acquired(surface, reused: false)))
        #expect(events.last == .shows(surface, .still))
    }

    /// Real lines from the 2026-09-28 soak: the kill-the-extension drill, the render-state drill, a check, and late seams.
    static func firstSoak() throws -> SoakLog {
        let url = try #require(Bundle.module.url(forResource: "soak-2026-09-28", withExtension: "log", subdirectory: "Fixtures"))
        return SoakLog(text: try String(contentsOf: url, encoding: .utf8))
    }

    @Test
    func `reads the first soak's ladder, verdict and metrics lines`() throws {
        let log = try Self.firstSoak()
        let events = log.entries.map(\.event)

        #expect(log.unparsed.isEmpty)
        let phases = events.compactMap { event -> HostPhase? in if case .hostStatus(let phase) = event { phase } else { nil } }
        #expect(phases == [
            .connecting, .live, .recovering(.flush), .recovering(.rebuildSurface), .recovering(.rebuildPipeline),
            .recovering(.restartAgent), .notSelected, .live,
        ])
        let tallies = events.compactMap { event -> PictureTally? in if case .counted(_, let tally) = event { tally } else { nil } }
        #expect(tallies.map { [$0.displayed, $0.expected] } == [[120, 120]])
        let verdicts = events.compactMap { event -> CheckVerdict? in if case .verdict(_, let verdict, 0) = event { verdict } else { nil } }
        #expect(verdicts == [.healthy])
        let metrics = events.compactMap { event -> MetricsLine? in if case .metrics(let line) = event { line } else { nil } }
        #expect(metrics.map(\.gapsOverLimitAtSeams) == [1, 1])
        #expect(metrics.map(\.largestSeamStep) == [1, 1])
    }

    @Test
    func `the first soak's drill is one episode, charged to the drill, that reached the restart`() throws {
        // 2026-09-28 13:10:21 +0100, as events.csv has it.
        let drill = SoakMarker(time: Date(timeIntervalSince1970: 1_790_597_421), kind: .drill, note: "killall the extension")

        let episodes = Episodes(log: try Self.firstSoak(), markers: [drill])

        #expect(episodes.all.map(\.outcome) == [.unrecovered(.reachedRestart)])
        #expect(episodes.all.map(\.trigger?.kind) == [.drill])
        #expect(episodes.all.map(\.subject) == [.host])
    }

    static let head = "2026-09-28 10:00:00.000000+0100 0x1     Default     0x0                  711    0    "
        + "WallpaperExtension: (WallpaperExtension.debug.dylib) "

    @Test
    func `counts and keeps a line it cannot read, never dropping it`() {
        let text = """
        Timestamp                       Thread     Type        Activity             PID    TTL
        \(Self.head)[app.livepaper.extension:extension] extension: woke source=system
        \(Self.head)[app.livepaper.extension:extension] extension: woken up
        \(Self.head)[app.livepaper.extension:supervisor] check started reason=wake surfaces=1
        """

        let log = SoakLog(text: text)

        #expect(log.unparsed.map(\.message) == ["extension: woken up"])
        #expect(log.entries.map(\.event) == [.woke(.system), .checkStarted(reason: "wake", surfaces: 1)])
        #expect(log.lines.count == 3)
    }

    @Test
    func `joins a message's continuation to its line`() {
        let text = """
        \(Self.head)[app.livepaper.extension:supervisor] render state unreadable, keeping generation=41: first line
        of the reason
        \(Self.head)[app.livepaper.extension:extension] extension: unlocked
        """

        let log = SoakLog(text: text)

        #expect(log.lines.first?.message == "render state unreadable, keeping generation=41: first line\nof the reason")
        #expect(log.unparsed.isEmpty)
        #expect(log.entries.map(\.event) == [.unlocked])
    }

    @Test
    func `reads a line once when two hourly exports overlap`() {
        let line = "\(Self.head)[app.livepaper.extension:extension] extension: unlocked"
        let text = [line, "Log      - Default:          1, Info:                0", "Timestamp   Thread", line].joined(separator: "\n")

        #expect(SoakLog(text: text).entries.count == 1)
    }
}
