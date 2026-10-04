import DesignSystem
import SwiftUI

struct SidebarRowPage: View {
    @State private var selection = "Favourites"

    private let library = [
        SidebarRowItem(id: "All Wallpapers", title: "All Wallpapers", systemImage: "photo.on.rectangle", badge: "128"),
        SidebarRowItem(id: "Favourites", title: "Favourites", systemImage: "heart", badge: "12"),
        SidebarRowItem(id: "Recents", title: "Recents", systemImage: "clock"),
        SidebarRowItem(id: "Playlists", title: "Playlists", systemImage: "rectangle.stack", badge: "3"),
    ]

    var body: some View {
        StateSection(
            title: "SidebarRowGroup",
            note: """
            Click to select, or Tab to the group and use the up and down arrows: it is one tab stop, like a list. Hover fades a \
            lighter fill in over 120 ms; the selection never animates. The rows are not glass: the panel is.
            """
        ) {
            panel {
                SidebarRowGroup("Library", selection: $selection, items: library)
            }
        }

        StateSection(
            title: "States",
            note: "Default, hovered (rest the pointer on any row), selected, with a badge, a long title truncating, and disabled."
        ) {
            panel {
                SidebarRow(title: "Default", systemImage: "folder") {}
                SidebarRow(title: "Hovered: point at me", systemImage: "cursorarrow") {}
                SidebarRow(title: "Selected", systemImage: "heart", isSelected: true) {}
                SidebarRow(title: "With a badge", systemImage: "tray", badge: "1,204") {}
                SidebarRow(title: "Selected with a badge", systemImage: "tray", badge: "7", isSelected: true) {}
                SidebarRow(title: "A playlist title far too long for a sidebar this narrow", systemImage: "rectangle.stack", badge: "48") {}
                SidebarRow(title: "Disabled", systemImage: "externaldrive", badge: "0") {}
                    .disabled(true)
            }
        }
    }

    private func panel(@ViewBuilder rows: () -> some View) -> some View {
        VStack(spacing: 0) {
            rows()
        }
        .padding(Spacing.small)
        .frame(width: 240)
        .layerSurface(
            .sidebar,
            in: RoundedRectangle(cornerRadius: Radius.outer(inner: Radius.control, padding: Spacing.small), style: .continuous)
        )
    }
}
