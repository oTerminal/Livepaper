import DesignSystem
import SwiftUI

struct TransportClusterPage: View {
    @State private var isPlaying = true
    @State private var lastAction = "Nothing pressed yet"

    var body: some View {
        StateSection(
            title: "Live",
            note: "Press play or pause: the symbol replaces itself and the triangle sits 1 pt right of centre. \(lastAction)."
        ) {
            TransportCluster(isPlaying: isPlaying) {
                lastAction = "Previous"
            } onPlayPause: {
                isPlaying.toggle()
                lastAction = isPlaying ? "Play" : "Pause"
            } onNext: {
                lastAction = "Next"
            }
        }

        StateSection(title: "Plain, playing", note: "For use inside a card or popover, which is already the surface.") {
            TransportCluster(isPlaying: true, onPrevious: {}, onPlayPause: {}, onNext: {})
        }

        StateSection(title: "Plain, paused") {
            TransportCluster(isPlaying: false, onPrevious: {}, onPlayPause: {}, onNext: {})
        }

        StateSection(title: "Glass, over a picture", note: "One capsule for all three buttons, never three glass circles.") {
            SamplePicture(seed: 3)
                .frame(width: 420, height: 240)
                .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                .overlay(alignment: .bottom) {
                    TransportCluster(isPlaying: isPlaying, style: .glass) {
                        lastAction = "Previous"
                    } onPlayPause: {
                        isPlaying.toggle()
                    } onNext: {
                        lastAction = "Next"
                    }
                    .padding(Spacing.large)
                }
        }

        StateSection(title: "Cannot skip", note: "A single wallpaper has nothing to skip to. The skip buttons keep their place.") {
            HStack(spacing: Spacing.extraLarge) {
                TransportCluster(isPlaying: true, canSkip: false, onPrevious: {}, onPlayPause: {}, onNext: {})
                TransportCluster(isPlaying: true, style: .glass, canSkip: false, onPrevious: {}, onPlayPause: {}, onNext: {})
            }
        }

        StateSection(title: "Disabled") {
            HStack(spacing: Spacing.extraLarge) {
                TransportCluster(isPlaying: false, onPrevious: {}, onPlayPause: {}, onNext: {})
                TransportCluster(isPlaying: false, style: .glass, onPrevious: {}, onPlayPause: {}, onNext: {})
            }
            .disabled(true)
        }
    }
}
