import AppKit
import DesignSystem
import SwiftUI

/// A menu-bar agent (`LSUIElement`) with a library window, which brings the Dock
/// icon while it is open, and Settings. The menu-bar item is AppKit's
/// (`MenuBarItem`), so its popover can be glass and run the design system's motion.
/// Every scene reads the one `AppModel` from its environment.
@main
struct LivepaperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Library", id: AppWindows.libraryID) {
            LibraryWindow()
                .environment(delegate.model)
                .environment(delegate.workshop)
                .libraryWindow(delegate.windows)
                .launchOptions(delegate.options)
        }
        .defaultSize(width: 1180, height: 760)
        // An agent opens no window at launch, and none comes back from the last run.
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
        .commands {
            // Sparkle's, where an app's menu has it: under About, above Settings.
            CommandGroup(after: .appInfo) {
                CheckForUpdatesCommand(updates: delegate.updates)
            }
            // Import, never Add: files and folders, as the Import button takes them.
            CommandGroup(replacing: .newItem) {
                Button("Import…") { delegate.model.chooseFilesToImport() }
                    .keyboardShortcut("o")
                Button("Wallpaper Engine Workshop") { delegate.windows.openWorkshop() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                Divider()
                DeleteWallpaperCommand(model: delegate.model)
            }
        }

        // Steam's Workshop pages, and Get.
        Window("Wallpaper Engine Workshop", id: AppWindows.workshopID) {
            WorkshopWindow()
                .environment(delegate.model)
                .environment(delegate.workshop)
                .workshopWindow(delegate.windows)
                .launchOptions(delegate.options)
        }
        .defaultSize(width: 1180, height: 820)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        // First-run onboarding, opened at launch when the preferences say it has not run.
        // Before it, the question of where Livepaper runs, when there is one.
        Window("Welcome to Livepaper", id: AppWindows.onboardingID) {
            OnboardingWindow()
                .environment(delegate.model)
                .environment(delegate.onboarding)
                .environment(delegate.installation)
                .onboardingWindow(delegate.windows)
                .launchOptions(delegate.options)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultWindowPlacement { _, _ in WindowPlacement(.center) }
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)

        Settings {
            SettingsView()
                .environment(delegate.model)
                .environment(delegate.workshop)
                .background(SceneActionsReader(windows: delegate.windows))
                .launchOptions(delegate.options)
        }
    }
}

/// Makes the model, on the real host or, with `-fakes YES`, on the fakes; puts
/// the menu-bar item up at launch; and holds Quit until the stopped render state
/// is written, so that each display is left holding its poster.
///
/// Where Livepaper runs is decided first (`Installation`). Asking for the
/// drag to Applications, or offering the move until it is answered, the launch
/// shows that card and nothing else: no menu-bar item, no model launch, so no
/// library read, host, sensors, hotkeys or socket, no doors, and nothing
/// registered or written, at quit included. Closing the card quits. Not Now
/// starts Livepaper as a launch that asks nothing does.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let options = LaunchOptions.current
    let windows = AppWindows()
    let model: AppModel
    /// The Workshop: Valve's steamcmd, or the fakes' stand-in.
    let workshop: WorkshopModel
    /// `livepaper://` links and the command socket.
    let doors: Doors
    /// First-run onboarding, decided as the app starts.
    let onboarding: Onboarding
    /// Where Livepaper runs, decided as the app starts, before onboarding shows.
    let installation: Installation
    /// Sparkle's updater, started with Livepaper.
    let updates: Updates
    /// The fakes run's world, which its Fakes menu drives. Nil when wired: then
    /// nothing fake is made, and the model drives the real wallpaper.
    private let fakes: Fakes?
    private var menuBarItem: MenuBarItem?
    /// Takes the fakes run's commands from a script; nil when wired.
    private var remote: FakesRemote?
    /// Whether Livepaper has started: false while the card asks where it runs,
    /// and for good after the drag was asked for.
    private var hasStarted = false
    /// What LaunchServices handed over before Livepaper started, opened once it does.
    private var heldURLs: [URL] = []

    override init() {
        let options = LaunchOptions.current
        if options.isFakes {
            let fakes = Fakes(library: options.fakeLibrary, onboarding: options.onboarding, install: options.install)
            self.fakes = fakes
            model = AppModel(services: fakes.makeServices())
        } else {
            fakes = nil
            model = AppModel(services: .wired())
        }
        workshop = WorkshopModel(services: options.isFakes ? .fakes() : .wired(), library: model)
        doors = Doors(model: model, windows: windows, workshop: workshop)
        onboarding = Onboarding(model: model)
        installation = Installation(services: fakes?.installServices() ?? .wired())
        updates = Updates(options: options)
        super.init()
        installation.startLivepaper = { [weak self] in self?.startLivepaper() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = options.nsAppearance
        if let fakes {
            remote = FakesRemote { [weak self] verb, rest in self?.perform(verb, rest, fakes: fakes) }
        }
        guard !installation.isAsking else {
            // A turn later, once SwiftUI has its scenes up: the card asks where Livepaper runs.
            Task { [windows] in windows.openOnboarding() }
            return
        }
        startLivepaper()
    }

    /// The menu-bar item, the model's launch, onboarding when it is due, the
    /// socket and the hotkeys: at launch, or once Not Now is answered.
    private func startLivepaper() {
        guard !hasStarted else { return }
        hasStarted = true
        let popover = PopoverView()
            .environment(model)
            .environment(windows)
            .background(SceneActionsReader(windows: windows))
        // The popover holds cards of `Radius.card`: 4 pt keeps them concentric with its 20 pt corners.
        let item = MenuBarItem(options: options, menu: menu, contentPadding: Spacing.tight, content: popover)
        windows.willOpenWindow = { [weak item] in item?.closePopover() }
        windows.didCloseLibrary = { [model] in model.libraryWindowDidClose() }
        workshop.showWorkshop = { [windows] in windows.openWorkshop() }
        menuBarItem = item
        watchHotkeys()
        model.launch()
        if onboarding.shows {
            // A turn later, once SwiftUI has its scenes up.
            Task { [windows] in windows.openOnboarding() }
        }
        if let socket = model.services.commandSocket {
            doors.openSocket(at: socket)
        }
        if !heldURLs.isEmpty {
            doors.open(heldURLs)
            heldURLs = []
        }
        updates.start()
    }

    /// Opening the app again, from Finder, the Dock, Spotlight or `open`, opens
    /// the library window: the menu-bar item alone can be hidden under the notch
    /// or by other items, and an agent otherwise shows nothing for the second open.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard hasStarted else { return true }
        windows.openLibrary()
        return false
    }

    /// `livepaper://` links. A link that launched the app arrives before
    /// `applicationDidFinishLaunching`; the model runs it once the launch has
    /// read the library. A file is left, with a log line: importing is done in
    /// the app's window alone. While the card asks where Livepaper runs, what
    /// arrives is held, and left if Livepaper never starts.
    func application(_ application: NSApplication, open urls: [URL]) {
        guard hasStarted || !installation.isAsking else {
            AppLog.logger.notice("\(AppLog.doorHeld(urls.count), privacy: .public)")
            heldURLs += urls
            return
        }
        doors.open(urls)
    }

    /// A command from the fakes remote. The popover opens and closes with
    /// motion, as a click would, so that a recording shows it.
    private func perform(_ verb: String, _ rest: String, fakes: Fakes) {
        switch (verb, rest) {
        case ("open", "popover"): menuBarItem?.openPopover(animated: true)
        case ("close", "popover"): menuBarItem?.closePopover(animated: true)
        case ("open", "library"): windows.openLibrary()
        case ("open", "settings"): windows.openSettings()
        case ("open", "workshop"): windows.openWorkshop()
        case ("menu", let title):
            let menu = fakes.menu(model: model) { [weak self] in self?.menuBarItem?.openPopover(animated: true) }
            if !menu.performItem(titled: title) { AppLog.logger.notice("fakes: no menu item \(title, privacy: .public)") }
        case ("quit", _): NSApp.terminate(nil)
        default:
            let commands = FakesCommands(model: model, doors: doors)
            let system = FakesSystemCommands(onboarding: onboarding, installation: installation, fakes: fakes, windows: windows)
            guard !commands.perform(verb, rest), !system.perform(verb, rest) else { return }
            AppLog.logger.notice("fakes: unknown command \(verb, privacy: .public) \(rest, privacy: .public)")
        }
    }

    /// Log Playback Metrics and Quit; the fakes run adds its Fakes submenu.
    private var menu: MenuBarItem.Menu {
        let fakesMenu: (() -> NSMenu)? = fakes.map { fakes in
            { [weak self, model] in
                fakes.menu(model: model) { self?.menuBarItem?.openPopover() }
            }
        }
        return MenuBarItem.Menu(
            checkForUpdates: { [updates] in updates.checkForUpdates() },
            canCheckForUpdates: { [updates] in updates.canCheck },
            isPlaybackMetricsOn: { [model] in model.isPlaybackMetricsOn },
            setPlaybackMetrics: { [model] in model.setPlaybackMetrics($0) },
            fakes: fakesMenu
        )
    }

    /// Closing the library window leaves the app in the menu bar. Closing the
    /// card that asks where Livepaper runs quits, since nothing else has started.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !hasStarted
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Nothing was started, so there is no stopped state to write.
        guard hasStarted else { return .terminateNow }
        // steamcmd runs in a session of its own, and would outlive the app.
        workshop.stopAll()
        doors.closeSocket()
        Task {
            await model.quit()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
