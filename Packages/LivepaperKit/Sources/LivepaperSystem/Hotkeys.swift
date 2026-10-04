import Carbon.HIToolbox
import LivepaperCore
import Observation
import os

/// What macOS answered a request for a hotkey.
nonisolated public enum HotkeyRegistration: Equatable, Sendable {
    case registered
    /// `eventHotKeyExistsErr`: another process holds the combination
    /// exclusively, as the Dock holds ⌘Tab, or this one holds it already.
    case taken
    /// Any other status, which says nothing about who has the combination.
    case failed(OSStatus)
}

/// Registers process-wide hotkeys, each under an identifier, and reports the
/// identifier of each one pressed. Injected, so that the seam's tests need no Carbon.
public protocol HotkeyRegistrar: AnyObject {
    /// Called with the identifier of each registered hotkey pressed.
    var onPress: ((UInt32) -> Void)? { get set }
    /// Registers `combination` under `id`, in place of whatever `id` had.
    func register(_ combination: KeyCombination, id: UInt32) -> HotkeyRegistration
    /// Releases what `id` has; nothing when it has nothing.
    func unregister(id: UInt32)
}

/// The global hotkeys, through Carbon, which needs no permission.
///
/// They start from `AppState.hotkeys` and report each change through
/// `onChange`, for the app model to save: it is the only writer of
/// `app-state.json`. A combination macOS does not grant stays assigned, since
/// it is the user's choice, and is asked for again at the next launch. A press
/// only calls `onPress`; what it does is the app's, and never animates.
@Observable
public final class Hotkeys {
    public static let logCategory = "hotkeys"

    /// The combination each action has.
    public private(set) var combinations: [HotkeyAction: KeyCombination]

    @ObservationIgnored private let registrar: any HotkeyRegistrar
    @ObservationIgnored private let logger: Logger
    @ObservationIgnored private let onChange: @MainActor ([HotkeyAction: KeyCombination]) -> Void
    @ObservationIgnored private let onPress: @MainActor (HotkeyAction) -> Void
    /// The actions whose combination macOS has granted.
    @ObservationIgnored private var registered: Set<HotkeyAction> = []

    /// What a trial registration, to learn whether a combination is free, is made under.
    private static let trialID: UInt32 = 0

    public init(
        combinations: [HotkeyAction: KeyCombination],
        registrar: any HotkeyRegistrar = CarbonHotkeyRegistrar(),
        logger: Logger = Logger(subsystem: LivepaperSystem.logSubsystem, category: Hotkeys.logCategory),
        onChange: @escaping @MainActor ([HotkeyAction: KeyCombination]) -> Void,
        onPress: @escaping @MainActor (HotkeyAction) -> Void
    ) {
        self.combinations = combinations
        self.registrar = registrar
        self.logger = logger
        self.onChange = onChange
        self.onPress = onPress
        registrar.onPress = { [weak self] id in self?.pressed(id) }
        for action in HotkeyAction.allCases {
            if let combination = combinations[action] { hold(combination, for: action) }
        }
    }

    /// Whether `action` can have `combination`: used by another Livepaper action,
    /// by name; else what macOS answers a trial registration, which is released
    /// at once. Only `eventHotKeyExistsErr` makes it taken elsewhere, so it never
    /// claims what macOS did not report.
    public func availability(of combination: KeyCombination, for action: HotkeyAction) -> HotkeyAvailability {
        let other = HotkeyAction.allCases.first { $0 != action && combinations[$0]?.hasSameKeys(as: combination) == true }
        if let other { return .usedBy(other) }
        // macOS answers "taken" to this process for what it already holds.
        if registered.contains(action), combinations[action]?.hasSameKeys(as: combination) == true { return .free }
        switch registrar.register(combination, id: Self.trialID) {
        case .registered:
            registrar.unregister(id: Self.trialID)
            return .free
        case .taken:
            return .takenElsewhere
        case .failed(let status):
            logger.error("hotkeys: asking for a combination failed with status \(status, privacy: .public)")
            return .free
        }
    }

    /// Gives `action` the combination, releasing the one it had; nil clears it.
    /// The one it has already is asked for again if macOS refused it before.
    public func assign(_ combination: KeyCombination?, to action: HotkeyAction) {
        let changed = combinations[action] != combination
        guard changed || (combination != nil && !registered.contains(action)) else { return }
        registrar.unregister(id: action.hotkeyID)
        registered.remove(action)
        combinations[action] = combination
        if let combination { hold(combination, for: action) }
        if changed { onChange(combinations) }
    }

    private func hold(_ combination: KeyCombination, for action: HotkeyAction) {
        switch registrar.register(combination, id: action.hotkeyID) {
        case .registered:
            registered.insert(action)
        case .taken:
            logger.notice("hotkeys: \(action.rawValue, privacy: .public) not registered: another process holds its combination")
        case .failed(let status):
            logger.error("hotkeys: \(action.rawValue, privacy: .public) not registered: status \(status, privacy: .public)")
        }
    }

    private func pressed(_ id: UInt32) {
        guard let action = HotkeyAction.allCases.first(where: { $0.hotkeyID == id }), registered.contains(action) else { return }
        onPress(action)
    }
}

extension HotkeyAction {
    /// What its hotkey is registered under. 0 is the trial's.
    fileprivate var hotkeyID: UInt32 {
        switch self {
        case .pauseOrResumeAll: 1
        case .nextWallpaper: 2
        case .mute: 3
        case .openLibrary: 4
        }
    }
}

extension KeyCombination {
    /// The key and its modifiers are what count, not how the layout printed the key.
    fileprivate func hasSameKeys(as other: KeyCombination) -> Bool {
        keyCode == other.keyCode && modifiers == other.modifiers
    }
}

/// Carbon's `RegisterEventHotKey`, with one handler on the application event target.
///
/// Every hotkey is registered exclusively. Without that, macOS accepts a
/// combination another process holds and tells both of a press, and
/// `eventHotKeyExistsErr` comes back only for one this process holds. With it,
/// a combination another process holds exclusively is refused, as the Dock's
/// ⌘Tab is, and ours is refused to other processes that ask for it exclusively.
/// Neither way reports shortcuts macOS keeps outside Carbon: ⌘Space and ⌘Q
/// both register. (Measured on macOS 27.)
public final class CarbonHotkeyRegistrar: HotkeyRegistrar {
    public var onPress: ((UInt32) -> Void)?

    /// "LVPR": another registrant's hotkey in this process is not taken for Livepaper's.
    nonisolated static let signature: OSType = 0x4C56_5052

    private let handles = CarbonHandles()

    public init() {}

    public func register(_ combination: KeyCombination, id: UInt32) -> HotkeyRegistration {
        installHandler()
        unregister(id: id)
        var reference: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(combination.keyCode),
            Self.carbonModifiers(combination.modifiers),
            EventHotKeyID(signature: Self.signature, id: id),
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &reference
        )
        switch status {
        case noErr:
            handles.hotkeys[id] = reference
            return .registered
        case OSStatus(eventHotKeyExistsErr):
            return .taken
        default:
            return .failed(status)
        }
    }

    public func unregister(id: UInt32) {
        guard let reference = handles.hotkeys.removeValue(forKey: id) else { return }
        UnregisterEventHotKey(reference)
    }

    /// Carbon's modifier bits for the recorder's.
    nonisolated public static func carbonModifiers(_ modifiers: KeyCombination.Modifiers) -> UInt32 {
        var carbon = 0
        if modifiers.contains(.control) { carbon |= controlKey }
        if modifiers.contains(.option) { carbon |= optionKey }
        if modifiers.contains(.shift) { carbon |= shiftKey }
        if modifiers.contains(.command) { carbon |= cmdKey }
        return UInt32(carbon)
    }

    private func installHandler() {
        guard handles.handler == nil else { return }
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // Unretained: the handler is removed when the handles go, with this registrar.
        let registrar = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), hotkeyPressed, 1, &pressed, registrar, &handles.handler)
    }

    fileprivate func pressed(_ id: UInt32) {
        onPress?(id)
    }
}

/// Carbon's handles for the registrar, released when it goes: the hotkeys, then the handler.
nonisolated private final class CarbonHandles {
    var hotkeys: [UInt32: EventHotKeyRef] = [:]
    var handler: EventHandlerRef?

    deinit {
        for reference in hotkeys.values {
            UnregisterEventHotKey(reference)
        }
        if let handler { RemoveEventHandler(handler) }
    }
}

/// Carbon calls it on the main thread, from the application's event loop.
nonisolated private func hotkeyPressed(
    _ call: EventHandlerCallRef?, _ event: EventRef?, _ registrar: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let registrar else { return OSStatus(eventNotHandledErr) }
    var id = EventHotKeyID()
    let status = GetEventParameter(
        event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id
    )
    guard status == noErr, id.signature == CarbonHotkeyRegistrar.signature else { return OSStatus(eventNotHandledErr) }
    let owner = Unmanaged<CarbonHotkeyRegistrar>.fromOpaque(registrar)
    let pressed = id.id
    MainActor.assumeIsolated {
        owner.takeUnretainedValue().pressed(pressed)
    }
    return noErr
}
