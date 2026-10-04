import DesignSystem
import LivepaperCore
import SwiftUI

/// The menu-bar popover's content: a card per connected display, the recent
/// wallpapers, and the footer. `MenuBarPopover` puts it on `GlassPopover`'s
/// glass with `Spacing.tight` around it, so the cards' `Radius.card` corners are
/// concentric with the panel's; nothing in it is glass.
struct PopoverView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            if model.libraryProblem == nil {
                ForEach(model.nowPlaying) { DisplayCard(card: $0) }
                RecentsSection()
            } else {
                // The library is empty to the model then, so the cards would say
                // "No wallpaper" over displays that still show what they had.
                LibraryProblemNotice()
            }
            Divider()
                .padding(.horizontal, Spacing.small)
            PopoverFooter()
                // The status line is last, and its 40 pt already keeps about 12 pt
                // under its words, the inset the popover keeps at its sides. The
                // glass's 4 pt, there for the cards' concentric corners, came on top
                // and left the words high, with more room under them than beside them.
                .padding(.bottom, -Spacing.tight)
        }
        .frame(width: PopoverMetrics.width)
    }
}

/// The last wallpapers set on a display, newest first. A click sets one on All
/// Displays. Already there when the popover opens, which it does often.
private struct RecentsSection: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let recents = model.recents
        if !recents.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.tight) {
                // The strip is labelled "Recent Wallpapers" for VoiceOver itself.
                Text("Recent Wallpapers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                RecentsStrip(items: recents.map(item), entrance: .none) { id in
                    model.setOnAllDisplays(.wallpaper(id))
                }
            }
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, Spacing.tight)
        }
    }

    private func item(_ wallpaper: Wallpaper) -> RecentItem<WallpaperID> {
        let poster = model.art.poster(for: wallpaper, size: PopoverMetrics.recentPosterSize)
        // The strip takes an `Image`, so one stands in while the poster is read.
        return RecentItem(id: wallpaper.id, poster: poster ?? .posterLoading, title: wallpaper.name)
    }
}

/// Said in place of the cards when the library could not be read at launch.
struct LibraryProblemNotice: View {
    var body: some View {
        EmptyState(
            title: "The library could not be read",
            message: "A newer Livepaper may have written it, or it is damaged. Livepaper leaves it as it is, "
                + "and the displays keep what they were showing.",
            systemImage: "exclamationmark.triangle"
        )
    }
}

/// The popover's sizes. Wide enough for a card's three lines beside its playlist
/// picker and transport; the posters are asked for at the size they are drawn.
enum PopoverMetrics {
    static let width: CGFloat = 400
    /// The size `DisplayNowPlayingCard` draws a display's poster at.
    static let cardPosterSize = CGSize(width: 64, height: 40)
    /// The size `RecentsStrip` draws each poster at.
    static let recentPosterSize = CGSize(width: 72, height: 45)
}

// MARK: Previews

extension AppModel {
    /// The model after `change`, for a preview's state: `.preview().previewing { $0.pauseAll() }`.
    func previewing(_ change: (AppModel) -> Void) -> AppModel {
        change(self)
        return self
    }

    /// The second display on the seeded playlist, for the previews.
    func previewOnPlaylist() {
        guard let display = displays.last, let playlist = playlists.first else { return }
        choosePlaylist(playlist.id, for: display.identity)
    }

    /// The first display paused by the user, for the previews.
    func previewPausingFirstDisplay() {
        guard let display = displays.first else { return }
        togglePause(on: display.identity)
    }
}

#Preview("Live") {
    PopoverPreview(model: .preview())
}

#Preview("Live, on a playlist") {
    PopoverPreview(model: .preview().previewing { $0.previewOnPlaylist() })
}

#Preview("Empty library") {
    PopoverPreview(model: .preview(.empty))
}

#Preview("Paused on one display, muted") {
    PopoverPreview(model: .preview().previewing { model in
        model.previewPausingFirstDisplay()
        model.setMuted(true)
    })
}

#Preview("Pause All") {
    PopoverPreview(model: .preview().previewing { $0.pauseAll() })
}

#Preview("Not selected") {
    PopoverPreview(model: .preview(hostStatus: .notSelected))
}

#Preview("Service not responding") {
    PopoverPreview(model: .preview(hostStatus: .recovering(.restartAgent)))
}

#Preview("Library could not be read") {
    GlassPopover(contentPadding: Spacing.tight) {
        LibraryProblemNotice()
            .frame(width: PopoverMetrics.width)
    }
    .fixedSize()
    .padding(Spacing.section)
}

/// The popover as the menu-bar item shows it.
private struct PopoverPreview: View {
    let model: AppModel

    var body: some View {
        GlassPopover(contentPadding: Spacing.tight) { PopoverView() }
            .fixedSize()
            .padding(Spacing.section)
            .environment(model)
            .environment(AppWindows())
    }
}
