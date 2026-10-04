import DesignSystem
import LivepaperCore
import SwiftUI

/// The library window: the sidebar, the grid with the imports under it, and
/// the inspector, under a toolbar with search, sort and Import. The whole
/// window takes a drop of files and folders; toasts rise over the grid.
struct LibraryWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(WorkshopModel.self) private var workshop
    @Environment(\.openWindow) private var openWindow
    @State private var isInspectorShown = true
    @State private var isDropTargeted: Bool
    @State private var prompt: NamePrompt?
    @State private var playlistToDelete: Playlist?

    /// The window opens with neither; a preview can show it asking a name, or under a drop.
    init(prompt: NamePrompt? = nil, isDropTargeted: Bool = false) {
        _prompt = State(initialValue: prompt)
        _isDropTargeted = State(initialValue: isDropTargeted)
    }

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            LibrarySidebar(ask: { prompt = $0 }, confirmDelete: { playlistToDelete = $0 })
                .navigationSplitViewColumnWidth(min: Layout.sidebarMinimum, ideal: Layout.sidebarIdeal)
        } detail: {
            content
                .inspector(isPresented: $isInspectorShown) {
                    LibraryInspector()
                        .inspectorColumnWidth(min: Layout.inspectorMinimum, ideal: Layout.inspectorIdeal, max: Layout.inspectorMaximum)
                }
                .toolbar { toolbar }
        }
        .searchable(text: $model.search, placement: .toolbar, prompt: "Search")
        .frame(minWidth: Layout.windowMinimum.width, minHeight: Layout.windowMinimum.height)
        .dropDestination(for: URL.self) { urls, _ in
            let files = urls.filter(\.isFileURL)
            guard model.canImport else { return false }
            // A link dragged from a browser to a Workshop item is got from Steam.
            let gotFromWorkshop = workshop.get(dropped: urls)
            if !files.isEmpty { model.importItems(at: files) }
            return gotFromWorkshop || !files.isEmpty
        } isTargeted: { isDropTargeted = $0 }
        .dropZoneOverlay(
            isTargeted: isDropTargeted && model.canImport,
            title: "Drop to Import",
            message: "Each file, Wallpaper Engine item or Workshop link becomes a wallpaper."
        )
        .pastesIntoLibrary()
        .namePrompt($prompt, commit: name)
        .confirmationDialog(
            "Delete “\(playlistToDelete?.name ?? "")”?",
            isPresented: Binding { playlistToDelete != nil } set: { if !$0 { playlistToDelete = nil } },
            presenting: playlistToDelete
        ) { playlist in
            // Return is a key press: the sidebar and the grid change without motion.
            Button("Delete Playlist", role: .destructive) {
                withoutAnimationIfKeyPress { model.deletePlaylist(playlist.id) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Its wallpapers stay in the library.")
        }
    }

    /// The grid, or why there is none, with the imports under it.
    private var content: some View {
        @Bindable var model = model
        return VStack(spacing: 0) {
            Group {
                if model.libraryProblem != nil {
                    LibraryProblemState()
                } else if let empty = model.emptyGrid {
                    LibraryEmptyState(reason: empty)
                } else {
                    WallpaperGrid(grid: model.grid, ask: { prompt = $0 })
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .toastHost($model.toasts) { model.undo($0) }

            if !model.importList.rows.isEmpty || !workshop.downloads.rows.isEmpty {
                Divider()
                WorkshopDownloadList()
                ImportListView()
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Picker("Sort By", selection: Binding { model.sortOrder } set: { model.setSortOrder($0) }) {
                    Text("Newest First").tag(Library.SortOrder.newestFirst)
                    Text("Oldest First").tag(Library.SortOrder.oldestFirst)
                    Text("Name").tag(Library.SortOrder.name)
                }
                .pickerStyle(.inline)
            } label: {
                Label("Sort", systemImage: "arrow.up.arrow.down")
            }
            // A playlist, and a display, keep their own order.
            .disabled(!model.section.followsSortOrder)
            .help("Sort")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Import", systemImage: "square.and.arrow.down") { model.chooseFilesToImport() }
                .disabled(!model.canImport)
                .help("Import")
        }
        ToolbarItem(placement: .primaryAction) {
            Button("Wallpaper Engine Workshop", systemImage: "globe") { openWindow(id: AppWindows.workshopID) }
                .disabled(!model.canImport)
                .help("Wallpaper Engine Workshop")
        }
        ToolbarItem(placement: .primaryAction) {
            Button(isInspectorShown ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.trailing") {
                withoutAnimationIfKeyPress { isInspectorShown.toggle() }
            }
            .help(isInspectorShown ? "Hide Inspector" : "Show Inspector")
        }
    }

    /// The name as typed: Core takes it, or refuses it and nothing changes. Where
    /// the sidebar goes after a new playlist is Core's too (`createPlaylist`).
    private func name(_ prompt: NamePrompt, _ name: String) {
        switch prompt {
        case .renameWallpaper(let id, _):
            model.rename(id, to: name)
        case .renamePlaylist(let id, _):
            model.renamePlaylist(id, to: name)
        case .newPlaylist(let wallpaper):
            model.createPlaylist(named: name, with: wallpaper.map { [$0] } ?? [])
        }
    }
}

private nonisolated enum Layout {
    static let windowMinimum = CGSize(width: 900, height: 560)
    static let sidebarMinimum: CGFloat = 200
    static let sidebarIdeal: CGFloat = 220
    /// Wide enough for the fit mode picker's three segments over the preview.
    static let inspectorMinimum: CGFloat = 320
    static let inspectorIdeal: CGFloat = 340
    static let inspectorMaximum: CGFloat = 440
}

#Preview("Library, seeded") {
    LibraryWindow()
        .frame(width: 1200, height: 760)
        .environment(AppModel.preview())
        .environment(WorkshopModel.preview())
}

#Preview("Library, empty") {
    LibraryWindow()
        .frame(width: 1200, height: 760)
        .environment(AppModel.preview(.empty))
        .environment(WorkshopModel.preview())
}

#Preview("A delete's undo toast") {
    LibraryWindow()
        .frame(width: 1200, height: 760)
        .environment(AppModel.preview().previewing { $0.delete($0.library.wallpapers[2].id) })
        .environment(WorkshopModel.preview())
}

#Preview("A plain toast: a duplicate") {
    LibraryWindow()
        .frame(width: 1200, height: 760)
        .environment(AppModel.preview().previewing { $0.showToast(.duplicate(of: $0.library.wallpapers[0])) })
        .environment(WorkshopModel.preview())
}

#Preview("A drop over the window") {
    LibraryWindow(isDropTargeted: true)
        .frame(width: 1200, height: 760)
        .environment(AppModel.preview())
        .environment(WorkshopModel.preview())
}

#Preview("Naming a new playlist") {
    LibraryWindow(prompt: .newPlaylist(with: nil))
        .frame(width: 1200, height: 760)
        .environment(AppModel.preview())
        .environment(WorkshopModel.preview())
}

#Preview("Renaming a wallpaper") {
    let model = AppModel.preview()
    LibraryWindow(prompt: .renameWallpaper(model.library.wallpapers[0].id, name: model.library.wallpapers[0].name))
        .frame(width: 1200, height: 760)
        .environment(model)
        .environment(WorkshopModel.preview())
}
