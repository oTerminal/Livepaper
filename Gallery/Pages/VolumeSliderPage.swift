import DesignSystem
import SwiftUI

struct VolumeSliderPage: View {
    @State private var isMuted = false
    @State private var volume = 0.6

    var body: some View {
        StateSection(
            title: "Levels",
            note: """
            The symbol follows the level and swaps with a symbol replace. The speaker and the readout sit in fixed slots, \
            so the slider never changes length. Every slider here is live.
            """
        ) {
            VStack(alignment: .leading, spacing: Spacing.small) {
                Sample(title: "0%", volume: 0)
                Sample(title: "35%", volume: 0.35)
                Sample(title: "100%", volume: 1)
            }
        }

        StateSection(title: "Muted", note: "Dimmed but usable: drag it and it unmutes.") {
            Sample(title: "Muted", volume: 0.6, isMuted: true)
        }

        StateSection(title: "Disabled") {
            Sample(title: "Disabled", volume: 0.5)
                .disabled(true)
        }

        StateSection(
            title: "Speaker showing the level",
            note: """
            speaker: .indicator, where the one mute is elsewhere (the popover's cards; Mute is its footer's). The speaker is \
            not a control, so it is secondary, like the readout, and has no target; it still shows the slash while muted, and \
            dragging unmutes. The row keeps the mute button's 40 pt height.
            """
        ) {
            VStack(alignment: .leading, spacing: Spacing.small) {
                Sample(title: "0%", volume: 0, speaker: .indicator)
                Sample(title: "60%", volume: 0.6, speaker: .indicator)
                Sample(title: "100%", volume: 1, speaker: .indicator)
                Sample(title: "Muted", volume: 0.6, isMuted: true, speaker: .indicator)
                Sample(title: "Disabled", volume: 0.5, speaker: .indicator)
                    .disabled(true)
            }
        }

        StateSection(
            title: "Muted from elsewhere",
            note: """
            A Mute toggle beside the slider, as the popover's footer is to its cards. Muting dims the slider and swaps the \
            speaker at once; dragging the slider unmutes, and the toggle follows.
            """
        ) {
            HStack(spacing: Spacing.large) {
                LabelToggle(
                    "Mute",
                    systemImage: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                    isOn: $isMuted
                )
                VolumeSlider(volume: $volume, isMuted: $isMuted, speaker: .indicator)
                    .frame(width: 280)
            }
        }
    }
}

private struct Sample: View {
    let title: String
    @State var volume: Double
    @State var isMuted = false
    var speaker = VolumeSliderSpeaker.muteButton

    var body: some View {
        HStack(spacing: Spacing.large) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
            VolumeSlider(volume: $volume, isMuted: $isMuted, speaker: speaker)
                .frame(width: 280)
        }
    }
}
