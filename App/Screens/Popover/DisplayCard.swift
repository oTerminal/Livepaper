import DesignSystem
import LivepaperCore
import SwiftUI

/// One connected display in the popover: what it shows, why it is not playing,
/// and its controls. A display showing a wallpaper has its playlist picker, its
/// transport and its volume; one showing nothing has Choose, which opens the library.
struct DisplayCard: View {
    @Environment(AppModel.self) private var model
    @Environment(AppWindows.self) private var windows
    let card: NowPlaying

    var body: some View {
        DisplayNowPlayingCard(
            displayName: model.display(card.display)?.name ?? "Display",
            title: card.wallpaper?.name,
            poster: card.wallpaper.flatMap { model.art.poster(for: $0, size: PopoverMetrics.cardPosterSize) },
            status: card.status,
            isActive: card.isPlaying
        ) {
            if card.wallpaper == nil {
                choose
            } else {
                controls
            }
        } footer: {
            if let wallpaper = card.wallpaper {
                volume(of: wallpaper)
            }
        }
    }

    /// The volume of the wallpaper the display shows: the value the inspector's
    /// slider edits, so a change in one shows in the other, and it reaches the
    /// display when the edit settles (`editSettles`), not on every step of a drag.
    /// Mute is the footer's, the app's one: here the speaker only shows the level,
    /// dimmed with the slider while muted, and moving the slider unmutes.
    private func volume(of wallpaper: Wallpaper) -> some View {
        VolumeSlider(
            volume: Binding { model.volume(of: wallpaper) } set: { model.editVolume($0, of: wallpaper.id) },
            isMuted: Binding { model.isMuted } set: { model.setMuted($0) },
            speaker: .indicator
        )
    }

    /// The transport, and the playlist picker under it, which names the playlist
    /// or says "No Playlist". Beside the transport the picker left the card's
    /// words too little room, and with its symbol alone nobody could see which
    /// playlist a display is on.
    private var controls: some View {
        VStack(alignment: .trailing, spacing: 0) {
            // Play and pause are the display's own pause; Pause All is the footer's.
            TransportCluster(
                isPlaying: !card.isUserPaused,
                style: .plain,
                canSkip: card.canSkip,
                onPrevious: { model.previous(on: card.display) },
                onPlayPause: { model.togglePause(on: card.display) },
                onNext: { model.next(on: card.display) }
            )
            PlaylistPicker(selection: playlist, playlists: model.playlistOptions, style: .plain) {
                model.startNewPlaylist()
                windows.openLibrary()
            }
            .controlSize(.small)
            // Its chevron ends under the Next symbol, not at the edge of that button's 40 pt target.
            .padding(.trailing, Spacing.small)
        }
    }

    private var choose: some View {
        CompactTextButton(title: Text("Choose…")) {
            model.chooseWallpaperInLibrary()
            windows.openLibrary()
        }
        .accessibilityLabel("Choose Wallpaper")
        .help("Choose a wallpaper in the library")
    }

    /// Chosen from the menu, by click or by keyboard: a key press must not animate the card.
    private var playlist: Binding<PlaylistID?> {
        Binding {
            card.playlist
        } set: { id in
            withoutAnimationIfKeyPress { model.choosePlaylist(id, for: card.display) }
        }
    }
}

#Preview("Showing a wallpaper, and nothing") {
    CardsPreview(model: .preview())
}

#Preview("On a playlist") {
    CardsPreview(model: .preview().previewing { $0.previewOnPlaylist() })
}

#Preview("Paused on one display") {
    CardsPreview(model: .preview().previewing { $0.previewPausingFirstDisplay() })
}

#Preview("Muted") {
    CardsPreview(model: .preview().previewing { $0.setMuted(true) })
}

#Preview("Pause All") {
    CardsPreview(model: .preview().previewing { $0.pauseAll() })
}

#Preview("Empty library") {
    CardsPreview(model: .preview(.empty))
}

/// The cards alone, in the popover's glass, as wide as the popover.
private struct CardsPreview: View {
    let model: AppModel

    var body: some View {
        GlassPopover(contentPadding: Spacing.tight) {
            VStack(spacing: Spacing.tight) {
                ForEach(model.nowPlaying) { DisplayCard(card: $0) }
            }
            .frame(width: PopoverMetrics.width)
        }
        .fixedSize()
        .padding(Spacing.section)
        .environment(model)
        .environment(AppWindows())
    }
}
