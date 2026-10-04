import DesignSystem
import SwiftUI

struct HotkeyRecorderPage: View {
    @State private var next: Hotkey?
    @State private var pause: Hotkey? = Self.pauseHotkey
    private static let pauseHotkey = Hotkey(keyCode: 35, modifiers: [.control, .option], keyLabel: "P")

    var body: some View {
        StateSection(
            title: "Unassigned",
            note: "How every hotkey ships. Click, then type a combination. Try ⌃⌥P to see a conflict, Esc to cancel, Delete to clear."
        ) {
            LabeledContent("Next wallpaper") {
                HotkeyRecorder("Next wallpaper", hotkey: $next) { $0 == pause ? "Pause or resume" : nil }
            }
        }

        StateSection(title: "Assigned", note: "The clear button does what Delete does while recording.") {
            LabeledContent("Pause or resume") {
                HotkeyRecorder("Pause or resume", hotkey: $pause) { $0 == next ? "Next wallpaper" : nil }
            }
        }

        StateSection(
            title: "Recording",
            note: "Held in the recording phase so it can be looked at: the accent ring is state, so it is a border. A click ends it."
        ) {
            LabeledContent("Next wallpaper") {
                HotkeyRecorder("Next wallpaper", hotkey: .constant(nil), phase: .recording) { _ in nil }
            }
        }

        StateSection(
            title: "Conflict",
            note: """
            Held in the conflict phase: a symbol and words in red, on the caption line that is always there. Too wide \
            for the recorder, the words hang from the field's trailing edge, so the field stays put. Recording continues.
            """
        ) {
            LabeledContent("Next wallpaper") {
                HotkeyRecorder(
                    "Next wallpaper",
                    hotkey: .constant(nil),
                    phase: .conflict(Self.pauseHotkey, with: "Pause or resume")
                ) { _ in nil }
            }
        }

        StateSection(title: "Every modifier", note: "Written in the system's order.") {
            HotkeyRecorder(
                "Example",
                hotkey: .constant(Hotkey(keyCode: 49, modifiers: [.control, .option, .shift, .command], keyLabel: "Space"))
            ) { _ in nil }
        }
    }
}
