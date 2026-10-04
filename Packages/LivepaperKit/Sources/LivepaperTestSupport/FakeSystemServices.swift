import LivepaperCore
import Observation

/// System services that change nothing on the Mac and remember what they were asked.
///
/// The login item flips at once. The combinations macOS keeps for itself are
/// taken elsewhere, and a combination another action has is used by it.
@MainActor
@Observable
public final class FakeSystemServices: SystemServices {
    /// Settable, so that every state the login row can show can be shown.
    public var loginItem: LoginItemStatus
    /// What turning the login item on answers: on, or, as macOS can, needs
    /// approval or not found, for onboarding's login card.
    public var answerToTurningOn = LoginItemStatus.on
    public private(set) var hotkeys: [HotkeyAction: KeyCombination]
    public private(set) var loginItemsSettingsOpened = 0
    public private(set) var leaveCount = 0

    /// ⌘Q, ⌘W, ⌘Tab, ⌘Space, ⌃Space, ⌘H, ⌘M and ⌘, by virtual key code.
    private static let keptByMacOS: [(keyCode: UInt16, modifiers: KeyCombination.Modifiers)] = [
        (12, .command), (13, .command), (48, .command), (49, .command), (49, .control), (4, .command), (46, .command), (43, .command),
    ]

    public init(loginItem: LoginItemStatus = .off, hotkeys: [HotkeyAction: KeyCombination] = [:]) {
        self.loginItem = loginItem
        self.hotkeys = hotkeys
    }

    public func setOpenAtLogin(_ on: Bool) -> LoginItemStatus {
        loginItem = on ? answerToTurningOn : .off
        return loginItem
    }

    public func openLoginItemsSettings() {
        loginItemsSettingsOpened += 1
    }

    // The key and its modifiers are what count, not how the layout prints the key.
    public func availability(of combination: KeyCombination, for action: HotkeyAction) -> HotkeyAvailability {
        if Self.keptByMacOS.contains(where: { $0.keyCode == combination.keyCode && $0.modifiers == combination.modifiers }) {
            return .takenElsewhere
        }
        let other = HotkeyAction.allCases.first { other in
            other != action && hotkeys[other].map { $0.keyCode == combination.keyCode && $0.modifiers == combination.modifiers } == true
        }
        return other.map(HotkeyAvailability.usedBy) ?? .free
    }

    public func assign(_ combination: KeyCombination?, to action: HotkeyAction) {
        hotkeys[action] = combination
    }

    public func leaveLivepaper() async {
        leaveCount += 1
    }
}
