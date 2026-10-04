import Foundation
import LivepaperCore
@testable import LivepaperSystem
import Testing

/// "Copy diagnostics": what the report holds, and what it never says.
struct DiagnosticsReportTests {
    static let first = DisplayIdentity.numbered(1)
    static let second = DisplayIdentity.numbered(2)
    static let unplugged = DisplayIdentity.numbered(3)

    static func id(_ prefix: String, _ number: Int) -> UUID {
        UUID(uuidString: "\(prefix)-0000-0000-0000-00000000000\(number)") ?? UUID()
    }

    static let evening = Playlist(
        id: PlaylistID(uuid: id("BBBBBBBB", 1)), name: "Evening", wallpapers: [WallpaperID(uuid: id("AAAAAAAA", 1))],
        interval: .seconds(600), shuffle: false
    )

    /// The first display paused on a wallpaper, the second on Evening, one unplugged with its own, and a wallpaper on All Displays.
    static var state: AppState {
        var state = AppState()
        state.playlists = [evening]
        state.assignments = [
            first: .wallpaper(WallpaperID(uuid: id("AAAAAAAA", 1))),
            second: .playlist(evening.id),
            unplugged: .wallpaper(WallpaperID(uuid: id("AAAAAAAA", 3))),
        ]
        state.applyToAll = .wallpaper(WallpaperID(uuid: id("AAAAAAAA", 2)))
        state.rotation[second] = RotationState(current: WallpaperID(uuid: id("AAAAAAAA", 1)), position: 0, lastRotation: Moment.launch)
        state.pausedDisplays = [first]
        state.pauseRules = PauseRules(whenDesktopCovered: true, whenDisplayAsleepOrLocked: false, inLowPowerMode: true, onBattery: false)
        state.isMuted = true
        return state
    }

    static let redaction = Redaction(
        home: "/Users/jappleseed",
        userNames: ["jappleseed", "Johnny Appleseed", "applefan42"],
        wallpaperNames: ["Evening Tide"],
        fileNames: ["Beach Holiday.mov", "wallpaper.mov"]
    )

    static func line(_ message: String, category: String = "extension") -> ExtensionLogLine {
        ExtensionLogLine(timestamp: "2026-09-24 11:58:38.677991+0100", level: "Default", category: category, message: message)
    }

    static let log = ExtensionLogLines(
        lines: [
            line("extension: launched pid=12 version=0.1.0 build=1 bundle=/Users/jappleseed/Applications/Livepaper.app/Contents/X.appex"),
            line("render state read generation=4 stopped=false displays=1", category: "supervisor"),
            line("playback metrics for preview on AAAAAAAA-0000-0000-0000-000000000001/wallpaper.mov: loops 20", category: "surface"),
            line("scene: cannot load ~/Movies/Beach Holiday.mov for Johnny Appleseed (applefan42): <private>", category: "surface"),
            line("now showing \"Evening Tide\"", category: "supervisor"),
        ],
        selfCheck: line("bridge self-check: all present", category: "bridge"),
        problem: nil
    )

    static func report(
        host: RenderHostStatus = .live,
        loginItem: LoginItemStatus = .on,
        loginItemIntent: Bool? = true,
        store: WallpaperStoreShape = WallpaperStoreShape(store: .read(desktopEntries: 24, namingLivepaper: 24), keptCopyExists: true),
        log: ExtensionLogLines = log
    ) -> DiagnosticsReport {
        DiagnosticsReport(
            madeAt: Moment.launch,
            app: BundleVersion(version: "0.1.0", build: "7"),
            wallpaperExtension: BundleVersion(version: "0.1.0", build: "7"),
            machine: MachineFacts(macOS: "27.0 (26A428)", model: "Mac17,2"),
            isTranslocated: false,
            host: host,
            state: state,
            connected: [first, second],
            isPausedAll: false,
            loginItem: loginItem,
            loginItemIntent: loginItemIntent,
            store: store,
            extensionLog: log,
            redaction: redaction
        )
    }

    static func section(_ title: String, of report: DiagnosticsReport) -> [String]? {
        report.sections.first { $0.title == title }?.lines
    }

    // MARK: What it holds

    @Test func `every section is there, in order`() {
        #expect(Self.report().sections.map(\.title) == [
            "App", "Mac", "Wallpaper service", "Displays", "Pauses and mute", "Login item", "Wallpaper store",
            "Extension log, last 10 minutes",
        ])
    }

    @Test func `the app, the extension and the Mac`() {
        let report = Self.report()

        #expect(Self.section("App", of: report) == ["Livepaper 0.1.0 (7)", "Wallpaper extension 0.1.0 (7)", "Translocated: no"])
        #expect(Self.section("Mac", of: report) == ["macOS 27.0 (26A428)", "Hardware Mac17,2"])
        #expect(report.text.hasPrefix("Livepaper diagnostics, made 2026-09-21T14:13:20Z\n\nApp\n  Livepaper 0.1.0 (7)\n"))
    }

    @Test func `the wallpaper service's status and the extension's self-check`() {
        #expect(Self.section("Wallpaper service", of: Self.report(host: .recovering(.rebuildSurface))) == [
            "Status: recovering(rebuildSurface)",
            "Self-check: bridge self-check: all present, at 2026-09-24 11:58:38.677991+0100",
        ])
    }

    @Test func `each display by its UUID, its assignment by ID`() {
        #expect(Self.section("Displays", of: Self.report()) == [
            "DDDDDDDD-0000-0000-0000-000000000001: wallpaper AAAAAAAA-0000-0000-0000-000000000001, paused",
            "DDDDDDDD-0000-0000-0000-000000000002: playlist BBBBBBBB-0000-0000-0000-000000000001, "
                + "showing AAAAAAAA-0000-0000-0000-000000000001, last rotation 2026-09-21T14:13:20Z",
            "DDDDDDDD-0000-0000-0000-000000000003, not connected: wallpaper AAAAAAAA-0000-0000-0000-000000000003",
            "All Displays: wallpaper AAAAAAAA-0000-0000-0000-000000000002",
        ])
    }

    @Test func `the pause rules, the pauses and mute`() {
        #expect(Self.section("Pauses and mute", of: Self.report()) == [
            "Pause rules: desktop covered on, display asleep or locked off, Low Power Mode on, on battery off",
            "Paused displays: DDDDDDDD-0000-0000-0000-000000000001",
            "Pause All: off",
            "Mute: on",
        ])
    }

    static let loginItems: [Row<(LoginItemStatus, Bool?), [String]>] = [
        Row("on, as asked", (.on, true), ["Status: on", "Intent: on"]),
        Row("off in System Settings, though asked for", (.off, true), ["Status: off", "Intent: on"]),
        Row("waiting for approval", (.needsApproval, true), ["Status: needs approval", "Intent: on"]),
        Row("not found, never asked", (.notFound, nil), ["Status: not found", "Intent: none recorded"]),
        Row("off, as asked", (.off, false), ["Status: off", "Intent: off"]),
    ]

    @Test(arguments: loginItems)
    func `the login item's status and the intent kept for it`(row: Row<(LoginItemStatus, Bool?), [String]>) {
        #expect(Self.section("Login item", of: Self.report(loginItem: row.input.0, loginItemIntent: row.input.1)) == row.expected)
    }

    static let stores: [Row<WallpaperStoreShape, [String]>] = [
        Row(
            "read, every Desktop entry naming Livepaper, the copy kept",
            WallpaperStoreShape(store: .read(desktopEntries: 24, namingLivepaper: 24), keptCopyExists: true),
            ["Desktop entries: 24", "Naming Livepaper: 24", "Kept copy: yes"]
        ),
        Row(
            "read, none naming Livepaper, no copy",
            WallpaperStoreShape(store: .read(desktopEntries: 2, namingLivepaper: 0), keptCopyExists: false),
            ["Desktop entries: 2", "Naming Livepaper: 0", "Kept copy: no"]
        ),
        Row(
            "unreadable",
            WallpaperStoreShape(store: .unreadable, keptCopyExists: true),
            ["Desktop entries: not read, the store is missing or unreadable", "Kept copy: yes"]
        ),
        Row(
            "of a shape this build does not know",
            WallpaperStoreShape(store: .unknownShape, keptCopyExists: false),
            ["Desktop entries: not read, the store is of a shape this build does not know", "Kept copy: no"]
        ),
    ]

    @Test(arguments: stores)
    func `the wallpaper store's shape, and nothing of its files`(row: Row<WallpaperStoreShape, [String]>) {
        #expect(Self.section("Wallpaper store", of: Self.report(store: row.input)) == row.expected)
    }

    @Test func `the extension's lines, each with its time, level and category`() {
        let lines = Self.section("Extension log, last 10 minutes", of: Self.report())

        #expect(lines?.count == 5)
        #expect(lines?[1] == "2026-09-24 11:58:38.677991+0100 Default [supervisor] render state read generation=4 stopped=false displays=1")
    }

    @Test func `a log that could not be read says why, and no self-check`() {
        let refused = ExtensionLogLines(problem: "log show exited with status 64: log: Must be admin to run 'show' command")
        let report = Self.report(log: refused)

        #expect(Self.section("Extension log, last 10 minutes", of: report) == [
            "Not read: log show exited with status 64: log: Must be admin to run 'show' command",
        ])
        #expect(Self.section("Wallpaper service", of: report)?.last == "Self-check: not read")
    }

    @Test func `a quiet extension has no lines to give`() {
        let report = Self.report(log: ExtensionLogLines(lines: [], selfCheck: nil, problem: nil))

        #expect(Self.section("Extension log, last 10 minutes", of: report) == ["No lines"])
        #expect(Self.section("Wallpaper service", of: report)?.last == "Self-check: none logged since the Mac started")
    }

    @Test func `a bundle's version and build come from its Info.plist`() throws {
        let folder = try TemporaryFolder()
        let bundle = folder.url.appending(path: "X.appex", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: bundle.appending(path: "Contents"), withIntermediateDirectories: true)
        let info: [String: Any] = [
            "CFBundleIdentifier": "app.livepaper.tests.x", "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "7",
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: bundle.appending(path: "Contents/Info.plist"))

        #expect(BundleVersion(bundle: try #require(Bundle(url: bundle))) == BundleVersion(version: "0.1.0", build: "7"))
    }

    @Test func `this Mac's version and model are read`() {
        let machine = MachineFacts.current()

        #expect(machine.macOS.hasPrefix("\(ProcessInfo.processInfo.operatingSystemVersion.majorVersion)."))
        #expect(machine.macOS.hasSuffix(")"))
        #expect(!machine.model.isEmpty && machine.model != "unknown")
    }

    // MARK: What it never says

    @Test func `no home path, user's name, Steam account, wallpaper's name, file name or hidden value is in it`() {
        let text = Self.report().text

        for secret in [
            "/Users/jappleseed", "jappleseed", "Johnny Appleseed", "applefan42", "Evening Tide", "Beach Holiday", "wallpaper.mov",
            "~/", "<private>", "/Applications",
        ] {
            #expect(!text.contains(secret), "\(secret) is in the report")
        }
        // The playlist's name is the user's too: playlists go by ID.
        #expect(!text.contains("Evening"))
    }

    @Test func `what the lines say otherwise is kept`() {
        #expect(Self.section("Extension log, last 10 minutes", of: Self.report()) == [
            "2026-09-24 11:58:38.677991+0100 Default [extension] extension: launched pid=12 version=0.1.0 build=1 bundle=<path>",
            "2026-09-24 11:58:38.677991+0100 Default [supervisor] render state read generation=4 stopped=false displays=1",
            "2026-09-24 11:58:38.677991+0100 Default [surface] playback metrics for preview on "
                + "AAAAAAAA-0000-0000-0000-000000000001/<file>: loops 20",
            "2026-09-24 11:58:38.677991+0100 Default [surface] scene: cannot load <path> for <user> (<user>): <hidden>",
            "2026-09-24 11:58:38.677991+0100 Default [supervisor] now showing \"<wallpaper>\"",
        ])
    }
}
