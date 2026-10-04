import AppKit
import SwiftUI

/// One playlist a `PlaylistPicker` offers.
public nonisolated struct PlaylistOption<ID: Hashable>: Identifiable {
    public let id: ID
    public let title: String
    /// How many wallpapers it holds; shown beside the title in the menu.
    public let count: Int

    public init(id: ID, title: String, count: Int) {
        self.id = id
        self.title = title
        self.count = count
    }
}

extension PlaylistOption: Sendable where ID: Sendable {}

/// Where a `PlaylistPicker` sits, which decides whether it brings its own surface.
public nonisolated enum PlaylistPickerStyle: Sendable {
    /// Among the inspector's controls, on a glass button of its own.
    case glass
    /// Inside a card or popover, which already is the surface: a borderless menu button.
    case plain
}

/// Chooses a playlist, or none: the one a wallpaper belongs to in the inspector,
/// the one a display shows in the menu-bar popover. A native menu, on a glass
/// button among the inspector's controls and borderless inside a card, where
/// glass would be glass on glass. A selection that matches no playlist reads as
/// "No Playlist" rather than as a blank.
public struct PlaylistPicker<ID: Hashable>: View {
    @Binding private var selection: ID?
    private let playlists: [PlaylistOption<ID>]
    private let style: PlaylistPickerStyle
    private let onCreate: () -> Void

    public init(
        selection: Binding<ID?>,
        playlists: [PlaylistOption<ID>],
        style: PlaylistPickerStyle = .glass,
        onCreate: @escaping () -> Void
    ) {
        _selection = selection
        self.playlists = playlists
        self.style = style
        self.onCreate = onCreate
    }

    private var current: PlaylistOption<ID>? {
        playlists.first { $0.id == selection }
    }

    public var body: some View {
        styled
            .fixedSize()
            .accessibilityLabel(Text("Playlist", bundle: .module))
            .accessibilityValue(current.map { Text(verbatim: $0.title) } ?? Text("No Playlist", bundle: .module))
    }

    @ViewBuilder private var styled: some View {
        switch style {
        case .glass:
            menu.buttonStyle(.glass)
        case .plain:
            menu.buttonStyle(.borderless)
        }
    }

    private var menu: some View {
        Menu {
            if !playlists.isEmpty {
                // An inline picker gives the menu its native checkmarks.
                Picker(selection: $selection) {
                    Text("No Playlist", bundle: .module)
                        .tag(ID?.none)
                    ForEach(playlists) { playlist in
                        Text(verbatim: playlist.title)
                            .badge(playlist.count)
                            .tag(ID?.some(playlist.id))
                    }
                } label: {
                    Text("Playlist", bundle: .module)
                }
                .pickerStyle(.inline)
                .labelsHidden()
                Divider()
            }
            Button(action: onCreate) {
                Text("New Playlist…", bundle: .module)
            }
        } label: {
            Label {
                if let current {
                    Text(verbatim: current.title)
                } else {
                    Text("No Playlist", bundle: .module)
                }
            } icon: {
                Image(nsImage: PlaylistSymbol.image)
            }
            .lineLimit(1)
        }
        .menuStyle(.button)
    }
}

/// The symbol beside the playlist's name. AppKit draws the menu's label as a
/// pop-up button, which takes its accessibility description from this image,
/// and a symbol's own description is its shape: VoiceOver said "Stack of
/// rectangles". Described as the control's label, it says "Playlist".
private enum PlaylistSymbol {
    static let image = NSImage(
        systemSymbolName: "rectangle.stack",
        accessibilityDescription: String(localized: "Playlist", bundle: .module)
    ) ?? NSImage()
}
