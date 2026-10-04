import DesignSystem
import SwiftUI

struct PlaylistPickerPage: View {
    @State private var none: Int?
    @State private var chosen: Int? = 2
    @State private var empty: Int?
    @State private var disabled: Int? = 1
    @State private var created = 0

    private let playlists = [
        PlaylistOption(id: 1, title: "Mornings", count: 12),
        PlaylistOption(id: 2, title: "Rainy Days", count: 7),
        PlaylistOption(id: 3, title: "Focus", count: 104),
    ]

    var body: some View {
        StateSection(title: "None selected", note: "New Playlist… chosen \(created) times.") {
            PlaylistPicker(selection: $none, playlists: playlists) { created += 1 }
        }

        StateSection(title: "One selected", note: "The menu checks the current playlist and shows each count.") {
            PlaylistPicker(selection: $chosen, playlists: playlists) { created += 1 }
        }

        StateSection(title: "Empty list", note: "Only New Playlist… is offered.") {
            PlaylistPicker(selection: $empty, playlists: []) { created += 1 }
        }

        StateSection(title: "Disabled") {
            PlaylistPicker(selection: $disabled, playlists: playlists) {}
                .disabled(true)
        }

        StateSection(
            title: "Plain, in a card",
            note: "Inside a card or a popover, which already is the surface: borderless, so there is no glass on glass."
        ) {
            GlassPopover(contentPadding: Spacing.tight) {
                DisplayNowPlayingCard(displayName: "Studio Display", title: "Slow Rain", poster: SamplePicture.image(seed: 11)) {
                    VStack(alignment: .trailing, spacing: 0) {
                        TransportCluster(isPlaying: true, onPrevious: {}, onPlayPause: {}, onNext: {})
                        PlaylistPicker(selection: $chosen, playlists: playlists, style: .plain) { created += 1 }
                            .controlSize(.small)
                            .padding(.trailing, Spacing.small)
                    }
                }
                .frame(width: 392)
            }
            .fixedSize()
        }
    }
}
