/// A key combination, as the recorder shows and reports it. The caller turns it
/// into whatever its hotkey service registers.
public nonisolated struct Hotkey: Hashable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Sendable {
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
    /// The key as the current keyboard layout prints it, such as "N" or "F5".
    public var keyLabel: String

    public init(keyCode: UInt16, modifiers: Modifiers, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    /// Modifiers in the order macOS writes them, then the key.
    public var displayString: String {
        let symbols: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1).joined() + keyLabel
    }
}

/// The hotkey recorder's behaviour: record, conflict, cancel, clear.
public nonisolated struct HotkeyRecorderState: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        case recording
        /// Still recording; the combination just tried belongs to something else.
        case conflict(Hotkey, with: String)
    }

    public enum Event: Sendable {
        case begin
        case key(Hotkey)
        /// Recording ended from outside, such as by losing focus.
        case cancel
        /// The clear button: what Delete does while recording, from any phase.
        case clear
    }

    public enum Effect: Equatable, Sendable {
        case changed(Hotkey?)
    }

    public private(set) var hotkey: Hotkey?
    public private(set) var phase = Phase.idle

    /// Unassigned and idle unless told otherwise: global hotkeys ship unassigned.
    /// A recorder can start in any phase, so a recording or a conflict can be
    /// shown without a key press.
    public init(hotkey: Hotkey? = nil, phase: Phase = .idle) {
        self.hotkey = hotkey
        self.phase = phase
    }

    public var isRecording: Bool {
        phase != .idle
    }

    /// `conflict` names what already uses a combination, or returns `nil` if it is free.
    @discardableResult
    public mutating func send(_ event: Event, conflict: (Hotkey) -> String?) -> Effect? {
        switch event {
        case .begin:
            phase = .recording
            return nil
        case .cancel:
            phase = .idle
            return nil
        case .clear:
            phase = .idle
            hotkey = nil
            return .changed(nil)
        case .key(let key):
            guard isRecording else { return nil }
            return record(key, conflict: conflict)
        }
    }

    private mutating func record(_ key: Hotkey, conflict: (Hotkey) -> String?) -> Effect? {
        if key.modifiers.isEmpty, key.keyCode == KeyCode.escape {
            phase = .idle
            return nil
        }
        if key.modifiers.isEmpty, KeyCode.deletes.contains(key.keyCode) {
            phase = .idle
            hotkey = nil
            return .changed(nil)
        }
        // Shift alone would swallow ordinary typing.
        guard !key.modifiers.subtracting(.shift).isEmpty || KeyCode.functionKeys.contains(key.keyCode) else {
            return nil
        }
        if key != hotkey, let owner = conflict(key) {
            phase = .conflict(key, with: owner)
            return nil
        }
        phase = .idle
        hotkey = key
        return .changed(key)
    }
}

/// Virtual key codes (Carbon's `kVK_` values), which do not depend on the layout.
private nonisolated enum KeyCode {
    static let escape: UInt16 = 53
    static let deletes: Set<UInt16> = [51, 117]
    /// F1 to F20.
    static let functionKeys: Set<UInt16> = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
    ]
}
