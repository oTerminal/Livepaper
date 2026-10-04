/// Core's form of the design system's `LoginItemState`, which Core cannot import.
public enum LoginItemStatus: Hashable, Sendable, CaseIterable {
    case off
    case on
    /// Registered, but the user has yet to allow it in System Settings.
    case needsApproval
    /// The system cannot find the app to register, usually because it is not in Applications.
    case notFound
}

/// What a global hotkey can do. Hotkeys ship unassigned.
public enum HotkeyAction: String, Hashable, Codable, Sendable, CaseIterable {
    case pauseOrResumeAll
    case nextWallpaper
    case mute
    case openLibrary

    public var title: String {
        switch self {
        case .pauseOrResumeAll: "Pause or Resume All"
        case .nextWallpaper: "Next Wallpaper"
        case .mute: "Mute"
        case .openLibrary: "Open Library"
        }
    }
}

/// A key and its modifiers, as the hotkey recorder records it.
public struct KeyCombination: Hashable, Codable, Sendable {
    /// The same bits as the design system's `Hotkey.Modifiers`, so the app maps one to the other by raw value.
    public struct Modifiers: OptionSet, Hashable, Codable, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let control = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let shift = Modifiers(rawValue: 1 << 2)
        public static let command = Modifiers(rawValue: 1 << 3)
    }

    /// The virtual key code, independent of the keyboard layout.
    public var keyCode: UInt16
    public var modifiers: Modifiers
    /// The key as the keyboard layout printed it when it was recorded.
    public var keyLabel: String

    public init(keyCode: UInt16, modifiers: Modifiers, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }
}

public enum HotkeyAvailability: Equatable, Sendable {
    case free
    /// Another Livepaper action has it.
    case usedBy(HotkeyAction)
    /// macOS or another app has it.
    case takenElsewhere

    /// What already uses the combination, for the recorder's "⌃⌥N is already
    /// used by …"; nil when it is free.
    public var owner: String? {
        switch self {
        case .free: nil
        case .usedBy(let action): action.title
        case .takenElsewhere: "macOS or another app"
        }
    }
}

/// The login item, the hotkeys and leaving Livepaper: what Settings talks to.
/// The real one talks to macOS; `FakeSystemServices` stands in until then.
@MainActor
public protocol SystemServices: AnyObject {
    var loginItem: LoginItemStatus { get }
    /// Asks for the login item on or off, and answers the status that follows
    /// in the same turn, so the switch never shows a state macOS does not have.
    func setOpenAtLogin(_ on: Bool) -> LoginItemStatus
    func openLoginItemsSettings()
    var hotkeys: [HotkeyAction: KeyCombination] { get }
    func availability(of combination: KeyCombination, for action: HotkeyAction) -> HotkeyAvailability
    /// Nil clears it.
    func assign(_ combination: KeyCombination?, to action: HotkeyAction)
    /// "Stop using Livepaper as wallpaper": puts the previous wallpaper back, then the app quits.
    func leaveLivepaper() async
}
