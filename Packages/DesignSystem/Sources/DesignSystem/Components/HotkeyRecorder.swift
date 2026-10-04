import AppKit
import SwiftUI

/// Records a global hotkey. Ships unassigned; shows a conflict and keeps
/// listening; Escape cancels and Delete clears.
///
/// Everything here is driven by key presses, so nothing animates.
public struct HotkeyRecorder: View {
    @Binding private var hotkey: Hotkey?
    @State private var state: HotkeyRecorderState
    @State private var monitor: Any?
    @FocusState private var isFocused: Bool

    private let label: String
    private let conflict: (Hotkey) -> String?

    /// `label` names what the hotkey does, for VoiceOver. `conflict` names what
    /// already uses a combination, or returns `nil` if it is free.
    ///
    /// `phase` is where the recorder starts. The app leaves it idle; the Gallery
    /// starts one recording, or in a conflict, to show those states without a
    /// key press. A recorder started that way is a picture of the state: it
    /// does not take key presses until it is clicked.
    public init(
        _ label: String,
        hotkey: Binding<Hotkey?>,
        phase: HotkeyRecorderState.Phase = .idle,
        conflict: @escaping (Hotkey) -> String?
    ) {
        self.label = label
        self.conflict = conflict
        _hotkey = hotkey
        _state = State(initialValue: HotkeyRecorderState(hotkey: hotkey.wrappedValue, phase: phase))
    }

    public var body: some View {
        RecorderLayout {
            field
            // The slot is always laid out, so the field never moves on the click
            // that starts recording, and rows in a trailing-aligned form line up.
            let showsClear = state.hotkey != nil && !state.isRecording
            clearButton
                .opacity(showsClear ? 1 : 0)
                .disabled(!showsClear)
                .accessibilityHidden(!showsClear)
            caption
        }
        .onChange(of: hotkey, initial: true) { _, hotkey in
            if state.hotkey != hotkey {
                state = HotkeyRecorderState(hotkey: hotkey)
            }
        }
        .onChange(of: isFocused) { _, isFocused in
            if !isFocused {
                send(.cancel)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { _ in
            send(.cancel)
        }
        .onDisappear(perform: stopListening)
    }

    private var field: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        return Button {
            send(state.isRecording ? .cancel : .begin)
        } label: {
            fieldText
                .font(.body)
                .monospacedDigit()
                .lineLimit(1)
                .padding(.horizontal, Spacing.medium)
                .frame(minWidth: Metrics.fieldWidth, minHeight: Metrics.fieldHeight)
                .background(.quaternary, in: shape)
                .overlay {
                    // State, so a border: the field is listening.
                    shape.strokeBorder(Color.accentColor, lineWidth: 2).opacity(state.isRecording ? 1 : 0)
                }
                .contentShape(.focusEffect, shape)
                // The visible field is compact; the pointer target is not.
                .frame(minHeight: Spacing.minimumHitArea)
                .contentShape(.interaction, .rect)
        }
        .buttonStyle(.press)
        .focused($isFocused)
        .accessibilityLabel(label)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(Text("Press to record a shortcut", bundle: .module))
    }

    private var fieldText: Text {
        if state.isRecording {
            Text("Type shortcut", bundle: .module).foregroundStyle(.secondary)
        } else if let hotkey = state.hotkey {
            Text(verbatim: hotkey.displayString)
        } else {
            Text("Record Shortcut", bundle: .module)
        }
    }

    private var clearButton: some View {
        Button {
            send(.clear)
        } label: {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
                .frame(width: Spacing.minimumHitArea, height: Spacing.minimumHitArea)
                .contentShape(.interaction, .rect)
                .contentShape(.focusEffect, .circle)
        }
        .buttonStyle(.press)
        .accessibilityLabel(Text("Clear shortcut", bundle: .module))
    }

    /// Always takes its line, so the rows below never jump when it changes.
    private var caption: some View {
        Group {
            if case .conflict(let tried, let owner) = state.phase {
                Label {
                    Text("\(tried.displayString) is already used by \(owner)", bundle: .module)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.red)
            } else if state.isRecording {
                Text("Esc to cancel, Delete to clear", bundle: .module)
                    .foregroundStyle(.secondary)
            } else {
                Text(verbatim: " ")
                    .accessibilityHidden(true)
            }
        }
        .font(.caption)
        .lineLimit(1)
    }

    private var accessibilityValue: Text {
        if state.isRecording {
            Text("Recording", bundle: .module)
        } else if let hotkey = state.hotkey {
            Text(verbatim: hotkey.displayString)
        } else {
            Text("None", bundle: .module)
        }
    }

    private func send(_ event: HotkeyRecorderState.Event) {
        withoutAnimation {
            if case .changed(let newHotkey) = state.send(event, conflict: conflict) {
                hotkey = newHotkey
            }
            if case .conflict(let tried, let owner) = state.phase {
                let message = String(localized: "\(tried.displayString) is already used by \(owner)", bundle: .module)
                AccessibilityNotification.Announcement(message).post()
            }
        }
        if state.isRecording {
            startListening()
        } else {
            stopListening()
        }
    }

    /// While recording, key presses go to the recorder and nowhere else, so
    /// Command-W or Command-Q can be recorded rather than obeyed.
    private func startListening() {
        guard monitor == nil else { return }
        isFocused = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { event in
            guard event.type == .keyDown else {
                // A click anywhere ends recording. Deferred, so a click on the
                // field itself reaches its button first and is not read as "begin".
                Task { send(.cancel) }
                return event
            }
            // Tab still moves focus, which ends recording: the recorder never traps the keyboard.
            if event.keyCode == 48, event.modifierFlags.isDisjoint(with: [.command, .control, .option]) {
                send(.cancel)
                return event
            }
            send(.key(Hotkey(event)))
            return nil
        }
    }

    private func stopListening() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private nonisolated enum Metrics {
        static let fieldWidth: CGFloat = 140
        static let fieldHeight: CGFloat = 28
    }
}

/// The field, the clear button's slot beside it, and the caption on the line
/// below, where `HotkeyRecorderCaption` puts it. Only the field and the slot
/// give the recorder its width.
private struct RecorderLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        frames(of: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, frames(of: subviews).frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size)
            )
        }
    }

    /// The field's baseline comes first, so a form row's label lines up with the field.
    func explicitAlignment(
        of guide: VerticalAlignment,
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGFloat? {
        let frames = frames(of: subviews).frames
        switch guide {
        case .firstTextBaseline:
            return bounds.minY + frames[0].minY + subviews[0].dimensions(in: .unspecified)[guide]
        case .lastTextBaseline:
            return bounds.minY + frames[2].minY + subviews[2].dimensions(in: .unspecified)[guide]
        default:
            return nil
        }
    }

    private func frames(of subviews: Subviews) -> (frames: [CGRect], size: CGSize) {
        let field = subviews[0].sizeThatFits(.unspecified)
        let slot = subviews[1].sizeThatFits(.unspecified)
        let caption = subviews[2].sizeThatFits(.unspecified)
        let rowHeight = max(field.height, slot.height)
        let width = field.width + Spacing.tight + slot.width
        let captionX = HotkeyRecorderCaption.offset(width: caption.width, fieldWidth: field.width, recorderWidth: width)
        return (
            [
                CGRect(origin: CGPoint(x: 0, y: (rowHeight - field.height) / 2), size: field),
                CGRect(origin: CGPoint(x: field.width + Spacing.tight, y: (rowHeight - slot.height) / 2), size: slot),
                CGRect(origin: CGPoint(x: captionX, y: rowHeight + Spacing.tight), size: caption),
            ],
            CGSize(width: width, height: rowHeight + Spacing.tight + caption.height)
        )
    }
}

extension Hotkey {
    /// The combination a key-down event carries.
    public init(_ event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers = Modifiers()
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.command) { modifiers.insert(.command) }
        self.init(
            keyCode: event.keyCode,
            modifiers: modifiers,
            keyLabel: event.keyCode == 49
                ? String(localized: "Space", bundle: .module)
                : Self.namedKeys[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "?"
        )
    }

    /// Keys whose characters are invisible or private-use, by virtual key code.
    private static let namedKeys: [UInt16: String] = [
        36: "↩", 48: "⇥", 51: "⌫", 53: "⎋", 76: "⌤", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10",
        103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
    ]
}
