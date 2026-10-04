import AppKit
import LivepaperCore
import LivepaperSystem
import Observation

/// The system services and what the app needs of them beyond Settings'
/// protocol: the real ones, or the fakes'.
struct SystemWiring {
    /// What Settings' login, hotkey and leave rows talk to.
    var services: any SystemServices
    /// At launch, once `app-state.json` has been read: the real ones register
    /// its hotkeys and square the login item with its intent.
    var start: (AppState, any SystemServicesOwner) -> Void
    /// Each hotkey pressed, in whatever app is in front; one reader, the app delegate.
    var hotkeyPresses: AsyncStream<HotkeyAction>
    /// Making Livepaper the system wallpaper: onboarding's last card.
    var selection: Selection
    /// System Settings at Wallpaper, where the user chooses Livepaper by hand.
    var wallpaperPane: any WallpaperPaneOpening

    /// `SMAppService`'s login item, Carbon's hotkeys, and `Selection` over
    /// WallpaperAgent's store, which the host's heartbeat says worked.
    static func mac(host: ExtensionHostClient) -> SystemWiring {
        let system = MacSystemServices(selection: Selection(host: host))
        return SystemWiring(
            services: system,
            start: { state, owner in system.start(kept: state, owner: owner) },
            hotkeyPresses: system.presses,
            selection: system.selection,
            wallpaperPane: WallpaperPane()
        )
    }
}

/// The app model, as the system services see it: the one writer of
/// `app-state.json`, where the hotkeys and the login item's intent are kept.
protocol SystemServicesOwner: AnyObject {
    func keep(hotkeys: [HotkeyAction: KeyCombination])
    func keep(loginItemIntent: LoginItemIntent)
}

/// The real `SystemServices`: the login item is `SMAppService.mainApp`,
/// the hotkeys are Carbon's, and leaving goes through `Selection`. Settings reads
/// it as it reads the fakes, and follows it: the login item's status is macOS's,
/// read again whenever the app becomes active or one of its windows becomes key,
/// since the user can change it in System Settings at any time.
@Observable
final class MacSystemServices: SystemServices {
    @ObservationIgnored let login: LoginItem
    /// Each hotkey pressed, in whatever app is in front: the app runs its action.
    @ObservationIgnored let presses: AsyncStream<HotkeyAction>
    @ObservationIgnored private let pressed: AsyncStream<HotkeyAction>.Continuation
    /// Leaving goes through it; onboarding's last card selects through it.
    @ObservationIgnored let selection: Selection
    /// Made at launch, from the combinations `app-state.json` kept.
    private var registrations: Hotkeys?
    @ObservationIgnored private weak var owner: (any SystemServicesOwner)?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    init(login: LoginItem = LoginItem(), selection: Selection) {
        self.login = login
        self.selection = selection
        (presses, pressed) = AsyncStream.makeStream()
        let center = NotificationCenter.default
        for name in [NSApplication.didBecomeActiveNotification, NSWindow.didBecomeKeyNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.login.refresh() }
            })
        }
    }

    /// At launch, once `app-state.json` has been read: its hotkeys are asked of
    /// macOS, and the login item is squared with the intent it kept, the answer
    /// kept when it differs. A translocated copy reconciles nothing and keeps
    /// nothing, since the next launch would be from another path.
    func start(kept state: AppState, owner: some SystemServicesOwner) {
        guard registrations == nil else { return }
        self.owner = owner
        registrations = Hotkeys(
            combinations: state.hotkeys,
            onChange: { [weak self] combinations in self?.owner?.keep(hotkeys: combinations) },
            onPress: { [pressed] action in pressed.yield(action) }
        )
        guard !login.bundle.isTranslocated else { return }
        if let answered = login.reconciling(state.loginItemIntent), answered != state.loginItemIntent {
            owner.keep(loginItemIntent: answered)
        }
    }

    // MARK: The login item

    var loginItem: LoginItemStatus { login.status }

    /// macOS's answer, in the same turn. What the user asked is kept with this
    /// copy of Livepaper, so that a launch can tell a copy that moved from the
    /// user turning it off in System Settings; never while translocated.
    func setOpenAtLogin(_ on: Bool) -> LoginItemStatus {
        let status = login.setOpenAtLogin(on)
        if !login.bundle.isTranslocated {
            owner?.keep(loginItemIntent: LoginItemIntent(openAtLogin: on, bundle: login.bundle))
        }
        return status
    }

    func openLoginItemsSettings() {
        login.openSystemSettingsLoginItems()
    }

    // MARK: Hotkeys

    var hotkeys: [HotkeyAction: KeyCombination] { registrations?.combinations ?? [:] }

    func availability(of combination: KeyCombination, for action: HotkeyAction) -> HotkeyAvailability {
        registrations?.availability(of: combination, for: action) ?? .free
    }

    func assign(_ combination: KeyCombination?, to action: HotkeyAction) {
        registrations?.assign(combination, to: action)
    }

    // MARK: Leaving

    /// "Stop using Livepaper as wallpaper": what each Desktop entry named before
    /// is put back from the kept copy, with one agent restart, and the copy goes;
    /// with no usable copy System Settings opens at Wallpaper for the user to
    /// choose. The login item is unregistered. The library is kept, and the
    /// caller quits the app. Should System Settings not open either, the words
    /// that send the user there are shown before the app quits.
    func leaveLivepaper() async {
        let outcome = await selection.leave()
        _ = setOpenAtLogin(false)
        guard case .failed = outcome, let words = outcome.words else { return }
        let alert = NSAlert()
        alert.messageText = "Your previous wallpaper could not be put back"
        alert.informativeText = words
        NSApp.activate()
        alert.runModal()
    }
}
