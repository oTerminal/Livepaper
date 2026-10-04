import DesignSystem
import LivepaperCore
import SwiftUI

/// The library window's sidebar: the library (All Wallpapers, Favourites), the
/// playlists in the user's order and New Playlist, and what each connected
/// display is showing. Each group is one tab stop; up and down move within it.
struct LibrarySidebar: View {
    @Environment(AppModel.self) private var model
    /// Rename… and New Playlist ask for a name.
    let ask: (NamePrompt) -> Void
    /// A playlist's Delete asks first: a playlist has no undo.
    let confirmDelete: (Playlist) -> Void

    var body: some View {
        @Bindable var model = model
        let counts = model.sidebarCounts
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.large) {
                group("Library") {
                    SidebarRowGroup("Library", selection: $model.section, items: [
                        SidebarRowItem(id: .all, title: "All Wallpapers", systemImage: "square.grid.2x2", badge: "\(counts.all)"),
                        SidebarRowItem(id: .favourites, title: "Favourites", systemImage: "heart", badge: "\(counts.favourites)"),
                    ])
                }

                group("Playlists") {
                    if !model.playlists.isEmpty {
                        SidebarRowGroup("Playlists", selection: $model.section, items: model.playlists.map { playlist in
                            SidebarRowItem(
                                id: .playlist(playlist.id),
                                title: playlist.name,
                                systemImage: "rectangle.stack",
                                badge: "\(counts.playlists[playlist.id] ?? 0)"
                            )
                        }) { section in
                            playlistMenu(section)
                        }
                    }
                    SidebarRow(title: "New Playlist", systemImage: "plus") {
                        ask(.newPlaylist(with: nil))
                    }
                }

                if !model.displays.isEmpty {
                    group("Now Playing") {
                        SidebarRowGroup("Now Playing", selection: $model.section, items: model.displays.map { display in
                            SidebarRowItem(id: .nowPlaying(display.identity), title: display.name, systemImage: "display")
                        })
                    }
                }
            }
            .padding(.horizontal, Spacing.small)
            .padding(.vertical, Spacing.medium)
        }
    }

    private func group(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Spacing.tight) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, Spacing.small)
                .accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) {
                rows()
            }
        }
    }

    @ViewBuilder
    private func playlistMenu(_ section: LibrarySection) -> some View {
        if case .playlist(let id) = section, let playlist = model.playlists.first(where: { $0.id == id }) {
            Button("Rename…") { ask(.renamePlaylist(id, name: playlist.name)) }
            Divider()
            Button("Delete", role: .destructive) { confirmDelete(playlist) }
        }
    }
}

#Preview("Sidebar") {
    LibrarySidebar(ask: { _ in }, confirmDelete: { _ in })
        .frame(width: 240, height: 480)
        .environment(AppModel.preview())
}
