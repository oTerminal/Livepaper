import DesignSystem
import LivepaperCore
import SwiftUI

/// What the library window asks a name for: a wallpaper or playlist being
/// renamed, or a new playlist, which a wallpaper's menu starts with that wallpaper in it.
enum NamePrompt: Hashable, Identifiable {
    case renameWallpaper(WallpaperID, name: String)
    case renamePlaylist(PlaylistID, name: String)
    case newPlaylist(with: WallpaperID?)

    var id: Self { self }

    var title: String {
        switch self {
        case .renameWallpaper: "Rename Wallpaper"
        case .renamePlaylist: "Rename Playlist"
        case .newPlaylist: "New Playlist"
        }
    }

    var confirmTitle: String {
        switch self {
        case .renameWallpaper, .renamePlaylist: "Rename"
        case .newPlaylist: "Create"
        }
    }

    /// What the field starts with.
    var name: String {
        switch self {
        case .renameWallpaper(_, let name), .renamePlaylist(_, let name): name
        case .newPlaylist: ""
        }
    }
}

extension View {
    /// Asks for a name in a sheet on the window, and hands `commit` the name as
    /// typed, for Core to take as it takes any name. Cancel, or Escape, leaves
    /// everything as it was.
    func namePrompt(_ prompt: Binding<NamePrompt?>, commit: @escaping (NamePrompt, String) -> Void) -> some View {
        sheet(item: prompt) { prompt in
            NamePromptSheet(prompt: prompt, commit: commit)
        }
    }
}

/// A sheet, not an alert: an alert's field did not have focus when it opened
/// (Cancel had it), so typing went nowhere. Here the field has focus from the
/// start, with a rename's old name selected so that typing replaces it, and
/// Return is Create or Rename as soon as Core would take the name.
private struct NamePromptSheet: View {
    let prompt: NamePrompt
    let commit: (NamePrompt, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var selection: TextSelection?
    @FocusState private var isFieldFocused: Bool

    init(prompt: NamePrompt, commit: @escaping (NamePrompt, String) -> Void) {
        self.prompt = prompt
        self.commit = commit
        _name = State(initialValue: prompt.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            Text(prompt.title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            TextField("Name", text: $name, selection: $selection)
                .focused($isFieldFocused)
            HStack(spacing: Spacing.small) {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(prompt.confirmTitle) {
                    // Return is a key press: the sidebar and the grid change without motion.
                    withoutAnimationIfKeyPress { commit(prompt, name) }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(acceptedName(name) == nil)
            }
        }
        .padding(Spacing.extraLarge)
        .frame(width: Layout.width)
        // With keyboard navigation on, a button would take focus first.
        .defaultFocus($isFieldFocused, true)
        .onAppear {
            selection = TextSelection(range: name.startIndex..<name.endIndex)
            isFieldFocused = true
        }
    }
}

private nonisolated enum Layout {
    /// Room for a long name without the sheet growing as it is typed.
    static let width: CGFloat = 340
}
