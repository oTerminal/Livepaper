import DesignSystem
import LivepaperCore
import SwiftUI

/// The inspector for the playlist the sidebar has selected, while no tile is:
/// its name, how many wallpapers it holds, Set on Display, and how it rotates.
struct PlaylistInspector: View {
    @Environment(AppModel.self) private var model
    let playlist: Playlist

    @State private var name: String
    @FocusState private var isNameFocused: Bool

    init(playlist: Playlist) {
        self.playlist = playlist
        _name = State(initialValue: playlist.name)
    }

    var body: some View {
        let assignment = Assignment.playlist(playlist.id)
        let count = model.sidebarCounts.playlists[playlist.id] ?? 0
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.extraLarge) {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    VStack(alignment: .leading, spacing: Spacing.tight) {
                        TextField("Name", text: $name)
                            .textFieldStyle(.plain)
                            .font(.title3.weight(.semibold))
                            .focused($isNameFocused)
                            .onSubmit(commitName)
                            .onChange(of: isNameFocused) { _, isFocused in
                                if !isFocused { commitName() }
                            }
                            .help("Rename")
                        Text("^[\(count) wallpaper](inflect: true)")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    SetOnDisplayButton(
                        targets: model.setOnDisplayTargets(for: assignment),
                        state: model.setOnDisplayState(for: assignment)
                    ) { target in
                        model.setOnDisplay(assignment, target: target)
                    }
                }

                InspectorSection("Rotation") {
                    // Labels trailing and controls leading, on one edge, as the details are.
                    Grid(alignment: .leading, horizontalSpacing: Spacing.medium, verticalSpacing: Spacing.small) {
                        GridRow {
                            // The controls carry their own labels for VoiceOver.
                            Text("Every")
                                .gridColumnAlignment(.trailing)
                                .accessibilityHidden(true)
                            Picker("Every", selection: interval) {
                                ForEach(Playlist.intervalChoices(including: playlist.interval), id: \.self) { choice in
                                    Text(choice.formatted(.units(allowed: [.days, .hours, .minutes], width: .wide)))
                                        .tag(choice)
                                }
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        GridRow {
                            Text("Shuffle")
                                .accessibilityHidden(true)
                            Toggle("Shuffle", isOn: shuffle)
                                .labelsHidden()
                                .toggleStyle(.switch)
                        }
                    }
                }
            }
            .padding(Spacing.large)
        }
        .onChange(of: playlist.name) { _, renamed in
            if !isNameFocused { name = renamed }
        }
    }

    /// Core decides the name, and the field shows what it decided: the name as
    /// kept, or the old one back when it was refused.
    private func commitName() {
        guard model.renamePlaylist(playlist.id, to: name), let renamed = model.playlists.first(where: { $0.id == playlist.id })?.name
        else {
            name = playlist.name
            return
        }
        name = renamed
    }

    private var interval: Binding<Duration> {
        Binding { playlist.interval } set: { model.setInterval($0, of: playlist.id) }
    }

    private var shuffle: Binding<Bool> {
        Binding { playlist.shuffle } set: { model.setShuffle($0, of: playlist.id) }
    }
}

/// What the inspector shows: the selected wallpaper; else the playlist the
/// sidebar has selected; else that nothing is selected.
struct LibraryInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let wallpaper = model.selectedWallpaper {
            // Its own state (the name being typed) goes with the selection.
            WallpaperInspector(wallpaper: wallpaper)
                .id(wallpaper.id)
        } else if let playlist = model.selectedPlaylist {
            PlaylistInspector(playlist: playlist)
                .id(playlist.id)
        } else {
            EmptyState(
                title: "No selection",
                message: "Select a wallpaper to change how it fits, its volume, and where it is set.",
                systemImage: "cursorarrow.and.square.on.square.dashed"
            )
        }
    }
}

#Preview("Playlist inspector") {
    let model = AppModel.preview()
    PlaylistInspector(playlist: model.playlists[0])
        .frame(width: 320, height: 480)
        .environment(model)
}

#Preview("Nothing selected") {
    LibraryInspector()
        .frame(width: 320, height: 480)
        .environment(AppModel.preview())
}
