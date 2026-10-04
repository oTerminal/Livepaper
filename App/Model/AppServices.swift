import AppKit
import LivepaperCore
import LivepaperImport
import LivepaperScene
import LivepaperSystem
import LivepaperTestSupport

/// What the model runs on: the real render host, stores, importer and sensors,
/// or the fakes (`Fakes`). Nothing else differs between the two runs.
struct AppServices {
    var isFakes: Bool
    var host: any RenderHost
    var libraryStore: any LibraryStore
    var appStateStore: any AppStateStore
    var art: WallpaperArt.Source
    /// The login item, the hotkeys, selecting and leaving: `SystemWiring.mac`
    /// wired, `FakeSystemServices` and a fake store on fakes.
    var system: SystemWiring
    /// Onboarding's record, whether a Livepaper ran here before, and the samples.
    var onboarding: OnboardingServices
    /// Clears what an import that was killed left behind; runs at launch, before any import.
    var sweep: () throws -> [URL]
    /// The render state the last run wrote, so that the generation carries on.
    /// Nil when there is none; throws when it cannot be read or trusted, which
    /// the model logs before starting from none.
    var lastRenderState: () throws -> RenderState?
    /// Made once, at launch, on the model: the one writer of the library.
    var makeImporter: (any ImportLibrary) -> any ImportRunning
    /// Prepares again, one at a time and off the main actor, the scenes whose
    /// programs are missing or were written by an older translator
    /// (`ScenePreparation.refresh`), then draws the poster of each scene that
    /// can be drawn and whose poster was not drawn from it by this build
    /// (`ScenePoster.refresh`); `prepared` and `drawn` hear each outcome. Runs at
    /// launch, after the sweep. Nothing in the fakes run.
    var prepareScenes: (
        _ wallpapers: [Wallpaper],
        _ prepared: @escaping @Sendable (Wallpaper, ScenePreparation.Outcome) async -> Void,
        _ drawn: @escaping @Sendable (Wallpaper, ScenePoster.Outcome) async -> Void
    ) async -> Void
    /// The sensors behind the pause rules and the connected displays.
    var makeSensing: (_ rules: PauseRules, _ onChange: @escaping @MainActor (SensedConditions) -> Void) -> ConditionsSensing
    var displayName: (ConnectedDisplay) -> String
    /// Moves a deleted wallpaper's folder to the Trash, once its undo is gone.
    var trash: (WallpaperID) throws -> Void
    /// Whether a wallpaper's files are still in the library; a card reads "Files missing" when not.
    var hasFiles: (Wallpaper) -> Bool
    /// "Log Playback Metrics", the extension's probe: never kept, so every launch starts with it off.
    var isPlaybackMetricsOn: () -> Bool
    var setPlaybackMetrics: (Bool) -> Void
    // The doors, rotation and diagnostics.
    /// Where the command socket the `livepaper` tool talks to is opened; nil in
    /// the fakes run, whose world is fake.
    var commandSocket: URL?
    /// The Mac's sleep and wake: a wake moves each playlist on (`RotationDriver`).
    var sleep: any SleepSensor
    /// The wallpaper store's shape, for the diagnostics report: counts only, read and never written.
    var storeShape: () -> WallpaperStoreShape
    /// The wallpaper extension's recent log lines, for the diagnostics report.
    var extensionLog: () async -> ExtensionLogLines
}

extension AppServices {
    /// The real thing: the library in Application Support, the wallpaper
    /// extension, the system's sensors.
    static func wired() -> AppServices {
        let location = LibraryLocation(home: .homeDirectory)
        let host = ExtensionHostClient(location: location)
        // The LGPL's relinking route: a replacement helper the user points at, else the bundled one.
        let replacement = UserDefaults.standard.string(forKey: "FFmpegReplacement").map {
            URL(filePath: ($0 as NSString).expandingTildeInPath)
        }
        // glslang and SPIRV-Cross, next to the executable as ffmpeg is. Without them scenes hold their posters.
        let shaderTools = ShaderTools.locate(
            bundled: Bundle.main.url(forAuxiliaryExecutable: "glslang"), Bundle.main.url(forAuxiliaryExecutable: "spirv-cross")
        )
        return AppServices(
            isFakes: false,
            host: host,
            libraryStore: FileLibraryStore(manifest: location.manifest),
            appStateStore: FileAppStateStore(file: location.appState),
            art: .library(location),
            system: .mac(host: host),
            // Looked for now, before this launch writes anything.
            onboarding: .wired(location: location),
            sweep: { try sweepInterruptedImports(in: location) },
            lastRenderState: { try lastRenderState(at: location.renderState) },
            makeImporter: { library in
                Importer(
                    location: location,
                    library: library,
                    ffmpeg: FFmpegTool.locate(replacement: replacement, bundled: Bundle.main.url(forAuxiliaryExecutable: "ffmpeg")),
                    shaderTools: shaderTools,
                    // A scene's poster is drawn by what draws it on the desktop.
                    sceneDrawing: WallpaperEngineScene.self
                )
            },
            prepareScenes: { wallpapers, prepared, drawn in
                _ = await ScenePreparation.refresh(wallpapers, in: location, tools: shaderTools, log: prepared)
                _ = await ScenePoster.refresh(wallpapers, in: location, drawingType: WallpaperEngineScene.self, log: drawn)
            },
            makeSensing: { rules, onChange in
                ConditionsSensing(rules: rules, host: host.capabilities, onChange: onChange)
            },
            displayName: { display in
                let screen = NSScreen.screens.first { $0.displayID == display.displayID }
                return screen?.localizedName ?? "Display \(display.displayID)"
            },
            trash: { id in
                let folder = location.wallpapers.appending(path: id.description, directoryHint: .isDirectory)
                try FileManager.default.trashItem(at: folder, resultingItemURL: nil)
            },
            hasFiles: { FileManager.default.fileExists(atPath: location.url(for: $0.optimisedCopy).path) },
            isPlaybackMetricsOn: { host.isPlaybackMetricsOn },
            setPlaybackMetrics: { host.setPlaybackMetrics($0) },
            commandSocket: location.commandSocket(fallback: .temporaryDirectory),
            sleep: SystemSleepSensor(),
            storeShape: { WallpaperStore(home: .homeDirectory).shape() },
            extensionLog: { await ExtensionLogLines.fetch() }
        )
    }

    /// What Settings' login, hotkey and leave rows talk to.
    var systemServices: any SystemServices { system.services }

    /// The render state in `file`; nil when there is none.
    private static func lastRenderState(at file: URL) throws -> RenderState? {
        let data: Data
        do {
            data = try Data(contentsOf: file)
        } catch let error as CocoaError where [.fileReadNoSuchFile, .fileNoSuchFile].contains(error.code) {
            return nil
        }
        return try RenderState.decode(data)
    }
}

extension NSScreen {
    /// CoreGraphics' number for this `NSScreen`'s display.
    fileprivate var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
