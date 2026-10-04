import DesignSystem
import SwiftUI

struct DisplayNowPlayingCardPage: View {
    @State private var isPlaying = true
    @State private var isMuted = false
    @State private var builtInVolume = 0.6
    @State private var studioVolume = 0.35
    private let posters = (0..<3).map { SamplePicture.image(seed: $0 + 10) }

    var body: some View {
        StateSection(title: "Playing") {
            DisplayNowPlayingCard(displayName: "Built-in Display", title: "Harbour at Dusk", poster: posters[0]) {
                TransportCluster(isPlaying: true, onPrevious: {}, onPlayPause: {}, onNext: {})
            }
            .frame(width: Layout.cardWidth)
        }

        StateSection(title: "Paused, with a status", note: "The poster is muted, and the status says why: colour is never the only cue.") {
            DisplayNowPlayingCard(
                displayName: "Studio Display",
                title: "Slow Rain",
                poster: posters[1],
                status: "Paused: on battery",
                isActive: false
            ) {
                TransportCluster(isPlaying: false, onPrevious: {}, onPlayPause: {}, onNext: {})
            }
            .frame(width: Layout.cardWidth)
        }

        StateSection(title: "Nothing assigned") {
            DisplayNowPlayingCard(displayName: "LG UltraFine", title: nil)
                .frame(width: Layout.cardWidth)
        }

        StateSection(title: "Long names", note: "Both lines truncate; the controls keep their size.") {
            DisplayNowPlayingCard(
                displayName: "Conference Room Projector (HDMI via Thunderbolt Dock)",
                title: "A wallpaper title far too long to fit beside three buttons",
                poster: posters[2],
                status: "Paused: another app is full screen on this display"
            ) {
                TransportCluster(isPlaying: true, canSkip: false, onPrevious: {}, onPlayPause: {}, onNext: {})
            }
            .frame(width: Layout.cardWidth)
        }

        StateSection(
            title: "In a GlassPopover",
            note: """
            Two cards in the popover they ship in, with 4 pt of padding so the corners are concentric: 20 = 16 + 4, and \
            16 = 8 + 8 for the poster. The panel is the glass; the cards are plain fills. Pause: the card keeps its height.
            """
        ) {
            GlassPopover(contentPadding: Spacing.tight) {
                VStack(spacing: Spacing.tight) {
                    DisplayNowPlayingCard(
                        displayName: "Built-in Display",
                        title: "Harbour at Dusk",
                        poster: posters[0],
                        status: isPlaying ? nil : "Paused",
                        isActive: isPlaying
                    ) {
                        TransportCluster(isPlaying: isPlaying, onPrevious: {}, onPlayPause: { isPlaying.toggle() }, onNext: {})
                    }
                    DisplayNowPlayingCard(displayName: "Studio Display", title: nil)
                }
                .frame(width: Layout.cardWidth)
            }
        }

        volumeSections
    }

    // MARK: The footer: volume, as the popover shows it

    @ViewBuilder private var volumeSections: some View {
        StateSection(
            title: "With a footer: volume",
            note: """
            A row as wide as the card under the poster, the words and the accessory: the popover's VolumeSlider, its speaker \
            showing the level only (Mute is the popover's footer). The speaker lines up with the poster's edge. Every slider here \
            is live.
            """
        ) {
            VStack(alignment: .leading, spacing: Spacing.small) {
                VolumeCard(displayName: "Built-in Display", title: "Harbour at Dusk", poster: posters[0], volume: 0.6)
                VolumeCard(
                    displayName: "Studio Display",
                    title: "Slow Rain",
                    poster: posters[1],
                    status: "Paused: on battery",
                    volume: 0.35
                )
                VolumeCard(displayName: "Built-in Display", title: "Harbour at Dusk", poster: posters[0], volume: 0.6, isMuted: true)
                VolumeCard(displayName: "Studio Display", title: "Slow Rain", poster: posters[1], volume: 0)
                VolumeCard(displayName: "Built-in Display", title: "Harbour at Dusk", poster: posters[0], volume: 1)
                VolumeCard(
                    displayName: "Conference Room Projector (HDMI via Thunderbolt Dock)",
                    title: "A wallpaper title far too long to fit beside three buttons",
                    poster: posters[2],
                    volume: 0.8
                )
            }
            .frame(width: Layout.cardWidth)
        }

        StateSection(
            title: "Volume in a GlassPopover",
            note: """
            Two displays and the popover's Mute under them, one mute for every display. Muting dims both sliders and slashes \
            both speakers at once; dragging either slider unmutes. A display showing nothing has no slider.
            """
        ) {
            GlassPopover(contentPadding: Spacing.tight) {
                VStack(alignment: .leading, spacing: Spacing.tight) {
                    DisplayNowPlayingCard(displayName: "Built-in Display", title: "Harbour at Dusk", poster: posters[0]) {
                        TransportCluster(isPlaying: true, onPrevious: {}, onPlayPause: {}, onNext: {})
                    } footer: {
                        VolumeSlider(volume: $builtInVolume, isMuted: $isMuted, speaker: .indicator)
                    }
                    DisplayNowPlayingCard(displayName: "Studio Display", title: "Slow Rain", poster: posters[1]) {
                        TransportCluster(isPlaying: true, onPrevious: {}, onPlayPause: {}, onNext: {})
                    } footer: {
                        VolumeSlider(volume: $studioVolume, isMuted: $isMuted, speaker: .indicator)
                    }
                    DisplayNowPlayingCard(displayName: "LG UltraFine", title: nil)
                    LabelToggle(
                        "Mute",
                        systemImage: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                        isOn: $isMuted
                    )
                }
                .frame(width: Layout.cardWidth)
            }
        }
    }
}

/// A card with the popover's volume footer, its slider live.
private struct VolumeCard: View {
    let displayName: String
    let title: String
    let poster: Image
    var status: String?
    @State var volume: Double
    @State var isMuted = false

    var body: some View {
        DisplayNowPlayingCard(displayName: displayName, title: title, poster: poster, status: status, isActive: status == nil) {
            TransportCluster(isPlaying: status == nil, onPrevious: {}, onPlayPause: {}, onNext: {})
        } footer: {
            VolumeSlider(volume: $volume, isMuted: $isMuted, speaker: .indicator)
        }
    }
}

private enum Layout {
    static let cardWidth: CGFloat = 340
}
