import DesignSystem
import SwiftUI

struct LabelButtonPage: View {
    @State private var isMuted = false
    @State private var isPausedAll = false
    @State private var lastPressed = "Nothing pressed yet"

    var body: some View {
        StateSection(
            title: "A line of controls on a popover",
            note: """
            Mute is a LabelToggle, Pause All a LabelButton whose words and symbol the caller swaps, then two SymbolButtons. \
            The symbols sit in fixed slots, so the words never move. Tab to one and press Space: nothing animates. \
            \(lastPressed).
            """
        ) {
            popover {
                LabelToggle("Mute", systemImage: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill", isOn: $isMuted)
                LabelButton(isPausedAll ? "Resume All" : "Pause All", systemImage: isPausedAll ? "play.fill" : "pause.fill") {
                    isPausedAll.toggle()
                }
                Spacer(minLength: Spacing.small)
                SymbolButton("Open Library", systemImage: "square.grid.2x2") { lastPressed = "Open Library pressed" }
                SymbolButton("Settings", systemImage: "gearshape") { lastPressed = "Settings pressed" }
            }
        }

        StateSection(
            title: "LabelToggle, off and on",
            note: "On is a primary pill at 14%, FitModePicker's; never the accent, which draws grey in a popover. It does not animate."
        ) {
            popover {
                LabelToggle("Mute", systemImage: "speaker.wave.2.fill", isOn: .constant(false))
                LabelToggle("Mute", systemImage: "speaker.slash.fill", isOn: .constant(true))
            }
        }

        StateSection(title: "LabelToggle on, Increase Contrast", note: "The pill rises to 30%, as FitModePicker's does.") {
            popover {
                LabelToggle("Mute", systemImage: "speaker.slash.fill", isOn: .constant(true))
            }
            .transformEnvironment(\.accessibilityOverrides) { $0.increaseContrast = true }
        }

        StateSection(title: "LabelButton", note: "Pause All and Resume All differ in width; buttons after a spacer stay put.") {
            popover {
                LabelButton("Pause All", systemImage: "pause.fill") {}
                LabelButton("Resume All", systemImage: "play.fill") {}
            }
        }

        StateSection(title: "SymbolButton", note: "A symbol in a 40 pt square; its title is the tooltip and what VoiceOver reads.") {
            popover {
                SymbolButton("Open Library", systemImage: "square.grid.2x2") {}
                SymbolButton("Settings", systemImage: "gearshape") {}
            }
        }

        StateSection(title: "Disabled") {
            popover {
                LabelToggle("Mute", systemImage: "speaker.slash.fill", isOn: .constant(true))
                LabelButton("Pause All", systemImage: "pause.fill") {}
                SymbolButton("Settings", systemImage: "gearshape") {}
            }
            .disabled(true)
        }
    }

    /// The controls in a row on the popover's glass, as the menu-bar popover's footer holds them.
    private func popover(@ViewBuilder controls: () -> some View) -> some View {
        GlassPopover(contentPadding: Spacing.tight) {
            HStack(spacing: 0) {
                controls()
            }
            .frame(width: 392, alignment: .leading)
        }
        .fixedSize()
    }
}
