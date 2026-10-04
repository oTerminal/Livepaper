import Foundation
import LivepaperCore
import LivepaperImport
import LivepaperSystem
import LivepaperTestSupport

/// What the fakes run's library starts with: `-fakeLibrary seeded` for screenshots.
enum FakeLibrary: String {
    case empty
    case seeded
}

/// The fakes run (`-fakes YES`): a render host, two displays and the sensors,
/// all fake, a library and app state in memory, and an importer that walks the
/// stages on the clock without reading a file. Nothing touches the wallpaper,
/// `render-state.json` or the extension. The Fakes menu drives it.
final class Fakes {
    static let builtIn = ConnectedDisplay(
        identity: DisplayIdentity(uuid: fixedUUID("D15A0000", 1)),
        displayID: 1,
        pixelSize: Size(width: 3024, height: 1964),
        frame: Rect(origin: Point(x: 0, y: 0), size: Size(width: 1512, height: 982)),
        topSafeAreaInset: 32
    )
    static let studio = ConnectedDisplay(
        identity: DisplayIdentity(uuid: fixedUUID("D15A0000", 2)),
        displayID: 2,
        pixelSize: Size(width: 5120, height: 2880),
        frame: Rect(origin: Point(x: 1512, y: 0), size: Size(width: 2560, height: 1440))
    )
    static let names = [builtIn.identity: "Built-in Retina Display", studio.identity: "Studio Display"]

    let host: FakeRenderHost
    let connectedDisplays = [builtIn, studio]
    let displays: FakeDisplaySensor
    let power = FakePowerSensor(PowerState())
    let lock = FakeLockSensor(false)
    let displaySleep = FakeDisplaySleepSensor([])
    let covered = FakeCoveredDisplaySensor([])
    /// The Mac's sleep and wake, for the rotation driver: "Sleep and Wake" in the Fakes menu.
    let sleep = FakeSleepSensor()
    let systemServices = FakeSystemServices()
    /// The first launch played for onboarding (`-onboarding`); nil for a run that onboarded before.
    let onboarding: FakeOnboarding?
    let onboardingRecord: InMemoryOnboardingRecord
    /// Where the run says Livepaper runs (`-install`); nil for Applications.
    let install: FakeInstall?
    /// `install move fails`, from the fakes remote: the next Move fails.
    var movesFail = false
    let selectionWorld: FakeSelectionWorld
    /// Hotkeys the fakes remote presses (`hotkey next`), since the fakes register none.
    let hotkeyPresses: AsyncStream<HotkeyAction>
    let pressHotkey: AsyncStream<HotkeyAction>.Continuation
    private let library: FakeLibrary
    private var isPlaybackMetricsOn = false

    init(library: FakeLibrary, onboarding: FakeOnboarding? = nil, install: FakeInstall? = nil) {
        self.library = library
        self.onboarding = onboarding
        self.install = install
        onboardingRecord = InMemoryOnboardingRecord(onboarding?.record ?? OnboardingRecord(onboardedVersion: BundleVersion.main.words))
        host = FakeRenderHost()
        // Connecting, then live after about a second; a set takes long enough to see it working.
        host.liveAfter = .seconds(1)
        host.applyDelay = .milliseconds(600)
        // Long enough to see Restart working.
        host.agentRestartTime = .milliseconds(800)
        // Onboarding starts with Livepaper not yet the wallpaper: the heartbeat says so.
        host.isSelected = onboarding?.isSelected ?? true
        selectionWorld = FakeSelectionWorld(host: host)
        (hotkeyPresses, pressHotkey) = AsyncStream.makeStream()
        displays = FakeDisplaySensor(connectedDisplays)
    }

    /// Fresh stores each time: one model per call.
    func makeServices() -> AppServices {
        let (library, state) = seeded(self.library)
        return AppServices(
            isFakes: true,
            host: host,
            libraryStore: InMemoryLibraryStore(library),
            appStateStore: InMemoryAppStateStore(state.map(AppStateLoad.loaded) ?? .missing),
            art: .drawn,
            system: SystemWiring(
                services: systemServices,
                start: { _, _ in },
                hotkeyPresses: hotkeyPresses,
                selection: selectionWorld.selection,
                wallpaperPane: selectionWorld.pane
            ),
            onboarding: onboardingServices(),
            sweep: { [] },
            lastRenderState: { nil },
            makeImporter: { library in
                FakeImporter(library: library, clock: ContinuousClock(), step: .milliseconds(300), makeWallpaper: Self.importedWallpaper)
            },
            prepareScenes: { _, _, _ in },
            makeSensing: { [host, displays, power, lock, displaySleep, covered] rules, onChange in
                ConditionsSensing(
                    rules: rules,
                    host: host.capabilities,
                    displays: displays,
                    power: power,
                    lock: lock,
                    displaySleep: displaySleep,
                    covered: covered,
                    onChange: onChange
                )
            },
            displayName: { Self.names[$0.identity] ?? "Display \($0.displayID)" },
            trash: { _ in },
            hasFiles: { _ in true },
            isPlaybackMetricsOn: { [weak self] in self?.isPlaybackMetricsOn ?? false },
            setPlaybackMetrics: { [weak self] in self?.isPlaybackMetricsOn = $0 },
            // No socket: the `livepaper` tool must not reach a fake world. The remote's `door socket` stands in.
            commandSocket: nil,
            sleep: sleep,
            // Livepaper selected on a Mac with one Space, the store kept from before it.
            storeShape: { WallpaperStoreShape(store: .read(desktopEntries: 2, namingLivepaper: 2), keptCopyExists: true) },
            // A subsystem nothing logs to: the report's section reads "No lines", and nothing real is read.
            extensionLog: { await ExtensionLogLines.fetch(subsystem: "app.livepaper.fakes") }
        )
    }

    // MARK: The Fakes menu's controls

    /// The first display, which the per-display conditions apply to.
    var firstDisplay: ConnectedDisplay { Self.builtIn }

    var isDesktopCovered: Bool { covered.latest?.contains(firstDisplay.identity) ?? false }
    var isDisplayAsleep: Bool { displaySleep.latest?.contains(firstDisplay.identity) ?? false }
    var isLocked: Bool { lock.latest ?? false }
    var isLowPowerMode: Bool { power.latest?.lowPowerMode ?? false }
    var isOnBattery: Bool { power.latest?.onBattery ?? false }

    func toggleDesktopCovered() {
        covered.send(toggling(firstDisplay.identity, in: covered.latest ?? []))
    }

    func toggleDisplayAsleep() {
        displaySleep.send(toggling(firstDisplay.identity, in: displaySleep.latest ?? []))
    }

    func toggleLocked() {
        lock.send(!isLocked)
    }

    func toggleLowPowerMode() {
        power.send(PowerState(lowPowerMode: !isLowPowerMode, onBattery: isOnBattery))
    }

    func toggleOnBattery() {
        power.send(PowerState(lowPowerMode: isLowPowerMode, onBattery: !isOnBattery))
    }

    private func toggling(_ display: DisplayIdentity, in displays: Set<DisplayIdentity>) -> Set<DisplayIdentity> {
        displays.contains(display) ? displays.subtracting([display]) : displays.union([display])
    }

    // MARK: Sample files

    /// Files to import, written to the temporary folder: two that import (one
    /// through the ffmpeg helper's stage), one whose name makes the fake importer
    /// fail, a Wallpaper Engine video item with its title and preview, and a
    /// Wallpaper Engine scene, which is skipped. The files are empty: the fake
    /// importer never reads them. The same files again are duplicates.
    func writeSampleFiles() throws -> [URL] {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Livepaper Fakes", directoryHint: .isDirectory)
        let files = FileManager.default
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        func write(_ data: Data, to path: String) throws -> URL {
            let url = folder.appending(path: path)
            try files.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            return url
        }
        let item = folder.appending(path: "2345678901", directoryHint: .isDirectory)
        let project = #"{"type": "video", "file": "rain.mp4", "title": "Forest Rain", "preview": "preview.jpg"}"#
        _ = try write(Data(project.utf8), to: "2345678901/project.json")
        _ = try write(Data(), to: "2345678901/rain.mp4")
        if let preview = DrawnPoster.jpeg(seed: 23) {
            _ = try write(preview, to: "2345678901/preview.jpg")
        }
        let scene = folder.appending(path: "3456789012", directoryHint: .isDirectory)
        _ = try write(Data(#"{"type": "scene", "title": "Orbit"}"#.utf8), to: "3456789012/project.json")
        return [
            try write(Data(), to: "Harbour at Night.mov"),
            try write(Data(), to: "Paper Boats.webm"),
            try write(Data(), to: "Unreadable fail.mov"),
            item,
            scene,
        ]
    }

    // MARK: Wallpapers

    /// What a fake import becomes: a 4K wallpaper with no files, its poster drawn from its identifier.
    nonisolated static func importedWallpaper(_ candidate: ImportCandidate, fingerprint: Fingerprint) -> Wallpaper {
        makeWallpaper(
            id: WallpaperID(uuid: UUID()),
            name: candidate.name,
            importedAt: Date(),
            fingerprint: fingerprint,
            details: WallpaperDetails(duration: 20, width: 3840, height: 2160, frameRate: 30, codec: "hevc", byteCount: 64_000_000)
        )
    }

    private nonisolated static func makeWallpaper(
        id: WallpaperID,
        name: String,
        isFavourite: Bool = false,
        importedAt: Date,
        fingerprint: Fingerprint,
        details: WallpaperDetails
    ) -> Wallpaper {
        let folder = "wallpapers/\(id)"
        guard let optimisedCopy = try? LibraryPath("\(folder)/wallpaper.mov"), let poster = try? LibraryPath("\(folder)/poster.heic") else {
            preconditionFailure("a wallpaper's identifier makes a library path")
        }
        return Wallpaper(
            id: id,
            name: name,
            isFavourite: isFavourite,
            importedAt: importedAt,
            fingerprint: fingerprint,
            optimisedCopy: optimisedCopy,
            poster: poster,
            details: details
        )
    }

    /// Eight wallpapers, two of them favourites, a playlist of four, and one on
    /// the built-in display at 60% volume; the Studio Display is left with none.
    private func seeded(_ library: FakeLibrary) -> (Library, AppState?) {
        guard library == .seeded else { return (Library(), nil) }
        let now = Date()
        let samples = [
            Sample("Harbour at Dusk", seconds: 24, 3840, 2160, fps: 30, "hevc", megabytes: 71),
            Sample("Paper Lanterns", isFavourite: true, seconds: 12.5, 3840, 2160, fps: 60, "hevc", megabytes: 58),
            Sample("Northern Lights", isFavourite: true, seconds: 30, 5120, 2880, fps: 30, "hevc", megabytes: 142),
            Sample("Rain on Glass", seconds: 18, 2560, 1440, fps: 30, "h264", megabytes: 37),
            Sample("Forest Canopy", seconds: 20, 3840, 2160, fps: 24, "hevc", megabytes: 49),
            Sample("Tidal Pools", seconds: 9.6, 1920, 1080, fps: 60, "h264", megabytes: 22),
            Sample("Neon Alley", seconds: 15, 3840, 2160, fps: 30, "prores", megabytes: 410),
            Sample("Desert Dunes", seconds: 27, 3840, 1600, fps: 30, "hevc", megabytes: 66),
        ]
        var wallpapers = samples.enumerated().map { index, sample in
            Self.makeWallpaper(
                id: WallpaperID(uuid: fixedUUID("5EED0000", index + 1)),
                name: sample.name,
                isFavourite: sample.isFavourite,
                importedAt: now.addingTimeInterval(-Double(samples.count - index) * 26 * 60 * 60),
                fingerprint: Fingerprint(sha256: String(repeating: "0", count: 63) + String(index + 1)),
                details: sample.details
            )
        }
        // The one on the built-in display has its sound up, so the popover's and the
        // inspector's sliders show a level; the rest are silent, as an import leaves them.
        wallpapers[0].volume = 0.6
        var library = Library()
        for wallpaper in wallpapers {
            guard let next = try? library.inserting(wallpaper) else { preconditionFailure("the seeded wallpapers are distinct") }
            library = next
        }

        let ids = wallpapers.map(\.id)
        var state = AppState()
        state.playlists = [
            Playlist(
                id: PlaylistID(uuid: fixedUUID("5EED1000", 1)),
                name: "Evening Rotation",
                wallpapers: [ids[0], ids[2], ids[6], ids[3]],
                interval: Playlist.defaultInterval,
                shuffle: false
            ),
        ]
        state.assignments = [Self.builtIn.identity: .wallpaper(ids[0])]
        state.recents = [ids[0], ids[5], ids[1], ids[4]]
        return (library, state)
    }
}

/// One of the seeded wallpapers.
private struct Sample {
    let name: String
    let isFavourite: Bool
    let details: WallpaperDetails

    init(
        _ name: String, isFavourite: Bool = false,
        seconds: Double, _ width: Int, _ height: Int, fps: Double, _ codec: String, megabytes: Int
    ) {
        self.name = name
        self.isFavourite = isFavourite
        details = WallpaperDetails(
            duration: seconds, width: width, height: height, frameRate: fps, codec: codec, byteCount: megabytes * 1_000_000
        )
    }
}

/// Fixed identifiers, so the seeded library and the displays are the same on every run.
private func fixedUUID(_ prefix: String, _ number: Int) -> UUID {
    let digits = String(number)
    guard let uuid = UUID(uuidString: "\(prefix)-0000-0000-0000-\(String(repeating: "0", count: 12 - digits.count))\(digits)") else {
        preconditionFailure("not a UUID: \(prefix), \(number)")
    }
    return uuid
}
