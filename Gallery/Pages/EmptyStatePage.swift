import DesignSystem
import SwiftUI

struct EmptyStatePage: View {
    var body: some View {
        StateSection(title: "Library, empty", note: "One action. No entrance animation: this appears on navigation.") {
            frame {
                EmptyState(
                    title: "No wallpapers yet",
                    message: "Drop a video here, or choose one.",
                    systemImage: "photo.on.rectangle.angled",
                    actionTitle: "Choose Video…"
                ) {}
            }
        }

        StateSection(title: "Search, no results", note: "No action: the way out is the search field.") {
            frame {
                EmptyState(
                    title: "No results for “harbour”",
                    message: "Check the spelling, or search for something else.",
                    systemImage: "magnifyingglass"
                )
            }
        }

        StateSection(title: "Two actions", note: "The primary is prominent; the secondary is a link, so the two never compete.") {
            frame {
                EmptyState(
                    title: "No playlists",
                    message: "A playlist changes the wallpaper on a schedule.",
                    systemImage: "rectangle.stack",
                    actionTitle: "New Playlist",
                    action: {},
                    secondaryActionTitle: "Learn about playlists",
                    secondaryAction: {}
                )
            }
        }

        StateSection(title: "Very long message", note: "The text column has a maximum width, so lines stay short in any window.") {
            frame {
                EmptyState(
                    title: "This folder could not be read, and its name is long enough to wrap",
                    message: """
                    Livepaper does not have permission to read the folder you chose. Open System Settings, go to Privacy and \
                    Security, then Files and Folders, and allow Livepaper to read it. Then come back here and try again.
                    """,
                    systemImage: "folder.badge.questionmark",
                    actionTitle: "Try Again"
                ) {}
            }
        }

        StateSection(title: "Title only") {
            frame {
                EmptyState(title: "No favourites", systemImage: "heart")
            }
        }
    }

    /// Stands in for the content area of a window.
    private func frame(@ViewBuilder content: () -> some View) -> some View {
        content()
            .frame(maxWidth: 720, minHeight: 320)
            .background(.quinary, in: .rect(cornerRadius: Radius.card))
    }
}
