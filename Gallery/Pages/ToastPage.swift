import DesignSystem
import SwiftUI

struct ToastPage: View {
    @State private var presenter = ToastPresenter()
    @State private var count = 0
    @State private var lastUndone: String?

    var body: some View {
        StateSection(title: "Toast", note: "Says what happened.") {
            Toast(ToastItem(message: "3 wallpapers imported", systemImage: "checkmark.circle.fill")) {}
        }

        StateSection(title: "UndoToast", note: "A toast with an undo title.") {
            UndoToast(ToastItem(message: "Wallpaper deleted", systemImage: "trash", undoTitle: "Undo")) {}
        }

        StateSection(title: "Long message", note: "Two lines at most.") {
            Toast(
                ToastItem(
                    message: "“A title far too long to fit on one line of any toast” was removed from Evening Rotation",
                    undoTitle: "Undo"
                )
            ) {}
            .frame(maxWidth: 420)
        }

        StateSection(
            title: "Live",
            note: """
            Click quickly: a second toast replaces the first in place rather than queueing. It expires after 5 s, \
            holds while the pointer is over it, and Command-Z undoes it without animation.
            """
        ) {
            HStack(spacing: Spacing.medium) {
                Button("Delete a wallpaper") {
                    count += 1
                    presenter.send(.show(ToastItem(message: "Wallpaper \(count) deleted", systemImage: "trash", undoTitle: "Undo")))
                }
                Button("Import") {
                    presenter.send(.show(ToastItem(message: "3 wallpapers imported", systemImage: "checkmark.circle.fill")))
                }
                if let lastUndone {
                    Text("Undid: \(lastUndone)")
                        .foregroundStyle(.secondary)
                }
            }
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(.quaternary)
                .frame(height: 220)
                .overlay { Text("Window").foregroundStyle(.tertiary) }
                .toastHost($presenter) { id in
                    lastUndone = id.uuidString.prefix(8).description
                }
        }
    }
}
