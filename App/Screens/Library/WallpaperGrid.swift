import DesignSystem
import LivepaperCore
import SwiftUI

/// The section's wallpapers as tiles, one live at a time. One tile is selected:
/// a click selects it, the arrow keys, Home and End move it, and Delete, forward
/// delete or Edit > Delete deletes it; Command-Delete is `DeleteWallpaperCommand`'s.
/// The grid is one tab stop, like a native grid; none of what a key does animates.
struct WallpaperGrid: View {
    @Environment(AppModel.self) private var model
    let grid: [Wallpaper]
    let ask: (NamePrompt) -> Void

    @FocusState private var isFocused: Bool
    @State private var width: CGFloat = 0
    @State private var height: CGFloat = 0

    /// As many columns as fit tiles at least `Layout.minimumTileWidth` wide,
    /// which is also what the arrow keys move over.
    private var columns: Int {
        let usable = width - 2 * Layout.padding + Layout.columnSpacing
        return max(1, Int(usable / (Layout.minimumTileWidth + Layout.columnSpacing)))
    }

    var body: some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: Layout.columnSpacing, alignment: .top), count: columns),
                    spacing: Layout.rowSpacing
                ) {
                    ForEach(grid) { wallpaper in
                        tile(wallpaper)
                            .id(wallpaper.id)
                    }
                }
                .padding(Layout.padding)
                .frame(maxWidth: .infinity, minHeight: height, alignment: .top)
                // A click between the tiles selects nothing.
                .contentShape(.rect)
                .onTapGesture {
                    model.deselect()
                    isFocused = true
                }
                .livePreviewScope()
            }
            .onGeometryChange(for: CGSize.self, of: \.size) { size in
                width = size.width
                height = size.height
            }
            .focusable()
            .focused($isFocused)
            // The selected tile's ring says where the keys act; a ring round the whole grid would say nothing.
            .focusEffectDisabled()
            .onMoveCommand(perform: move)
            .onKeyPress(keys: [.home, .end]) { press in
                withoutAnimation { model.moveSelection(press.key == .home ? .first : .last, columns: columns) }
                return .handled
            }
            // macOS hands a focused view the Delete keys as the delete command, as
            // it hands it the arrows as move commands: a key press handler missed them.
            .onDeleteCommand {
                withoutAnimation { model.deleteSelected() }
            }
            .focusedValue(\.gridSelection, model.selection.selected)
            .onChange(of: model.selection.selected) { _, selected in
                guard let selected else { return }
                withoutAnimation { scroller.scrollTo(selected) }
            }
            .onAppear { isFocused = true }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Wallpapers")
        }
    }

    private func tile(_ wallpaper: Wallpaper) -> some View {
        WallpaperPoster(wallpaper) { poster in
            WallpaperTile(
                id: wallpaper.id,
                poster: poster ?? .posterLoading,
                title: wallpaper.name,
                isSelected: model.selection.selected == wallpaper.id,
                isFavourite: wallpaper.isFavourite
            ) {
                model.select(wallpaper.id)
                isFocused = true
            } livePreview: {
                // Without a hover preview (an import that made none, or the fakes run) the poster stays.
                if let url = model.art.hoverPreviewURL(for: wallpaper) {
                    // Clear: the preview fades in over the poster before its first frame is up.
                    PreviewPlayerView(url: url, presentation: Presentation(), backgroundColor: .clear)
                }
            }
        }
        // The grid is the tab stop; a tile is not.
        .focusable(false)
        .contextMenu {
            WallpaperMenu(wallpaper: wallpaper, ask: ask)
        }
    }

    private func move(_ direction: MoveCommandDirection) {
        let move: GridSelection.Move? = switch direction {
        case .left: .left
        case .right: .right
        case .up: .up
        case .down: .down
        @unknown default: nil
        }
        guard let move else { return }
        withoutAnimation { model.moveSelection(move, columns: columns) }
    }
}

/// A tile's context menu: set it on a display or all of them, favourite it,
/// rename it, put it in playlists or take it out, delete it. An item chosen with
/// Return is a key press, so what it changes (the toast, the grid, Set on
/// Display's state) does not animate.
struct WallpaperMenu: View {
    @Environment(AppModel.self) private var model
    let wallpaper: Wallpaper
    let ask: (NamePrompt) -> Void

    var body: some View {
        let assignment = Assignment.wallpaper(wallpaper.id)
        // A display already showing it is checked.
        ForEach(model.setOnDisplayTargets(for: assignment)) { target in
            Toggle("Set on \(target.name)", isOn: Binding { target.isCurrent } set: { _ in
                withoutAnimationIfKeyPress { model.setOnDisplay(assignment, target: target.id) }
            })
        }
        Button("Set on All Displays") {
            withoutAnimationIfKeyPress { model.setOnDisplay(assignment, target: SetOnDisplayTarget.allID) }
        }
        Divider()
        Button(wallpaper.isFavourite ? "Unfavourite" : "Favourite") {
            withoutAnimationIfKeyPress { model.toggleFavourite(wallpaper.id) }
        }
        Button("Rename…") { ask(.renameWallpaper(wallpaper.id, name: wallpaper.name)) }
        Menu("Playlists") {
            ForEach(model.playlists) { playlist in
                Toggle(playlist.name, isOn: Binding { playlist.wallpapers.contains(wallpaper.id) } set: { isIn in
                    withoutAnimationIfKeyPress {
                        if isIn {
                            model.add(wallpaper.id, to: playlist.id)
                        } else {
                            model.remove(wallpaper.id, from: playlist.id)
                        }
                    }
                })
            }
            if !model.playlists.isEmpty {
                Divider()
            }
            Button("New Playlist…") { ask(.newPlaylist(with: wallpaper.id)) }
        }
        Divider()
        Button("Delete", role: .destructive) {
            withoutAnimationIfKeyPress { model.delete(wallpaper.id) }
        }
        // Shown here; File > Delete Wallpaper takes the key while the grid has focus.
        .keyboardShortcut(.delete, modifiers: .command)
    }
}

/// File > Delete Wallpaper: Command-Delete without opening a menu. It acts only
/// while the grid has focus, so a text field keeps Command-Delete (delete to the
/// start of the line) for itself.
struct DeleteWallpaperCommand: View {
    let model: AppModel
    @FocusedValue(\.gridSelection) private var selected: WallpaperID?

    var body: some View {
        Button("Delete Wallpaper") {
            guard let selected else { return }
            // Mostly chosen by its key, and a key press never animates.
            withoutAnimation { model.delete(selected) }
        }
        .keyboardShortcut(.delete, modifiers: .command)
        .disabled(selected == nil)
    }
}

extension FocusedValues {
    /// The grid's selected wallpaper, while the grid has focus.
    @Entry var gridSelection: WallpaperID?
}

private nonisolated enum Layout {
    /// A tile narrower than this loses its title.
    static let minimumTileWidth: CGFloat = 180
    static let columnSpacing = Spacing.large
    static let rowSpacing = Spacing.extraLarge
    /// Room for the selection ring, 5 pt outside a tile, and more.
    static let padding = Spacing.extraLarge
}

#Preview("Grid") {
    let model = AppModel.preview()
    WallpaperGrid(grid: model.grid, ask: { _ in })
        .frame(width: 720, height: 520)
        .environment(model)
}
