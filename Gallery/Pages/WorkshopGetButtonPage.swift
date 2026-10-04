import DesignSystem
import SwiftUI

struct WorkshopGetButtonPage: View {
    @State private var live = WorkshopGetState.idle
    private let posters = (0..<3).map { SamplePicture.image(seed: $0 + 60) }

    var body: some View {
        StateSection(title: "Live", note: "Get, working for two seconds, then done. The title never moves; the icon slot changes.") {
            HStack(spacing: Spacing.medium) {
                WorkshopGetButton(state: live) {
                    live = .working
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        live = .done
                    }
                }
                Button("Reset") { live = .idle }
            }
        }

        StateSection(title: "All states", note: "Unavailable is disabled; its reason is the tooltip and what VoiceOver reads.") {
            HStack(spacing: Spacing.large) {
                WorkshopGetButton(state: .idle) {}
                WorkshopGetButton(state: .working) {}
                WorkshopGetButton(state: .done) {}
                WorkshopGetButton(state: .unavailable(reason: "Go to an item’s page to get it")) {}
            }
        }

        StateSection(
            title: "In the Workshop window's list",
            note: "Downloads are ImportProgressRows: steamcmd's steps as the detail, Steam's refusal as the failure."
        ) {
            VStack(spacing: Spacing.medium) {
                ImportProgressRow(title: "Lonely Cat", poster: posters[0], state: .queued) {}
                ImportProgressRow(
                    title: "Paper Lanterns", poster: posters[1], state: .running(fraction: nil, detail: "Starting Steam’s download tool")
                ) {}
                ImportProgressRow(
                    title: "Paper Lanterns", poster: posters[1], state: .running(fraction: 0.43, detail: "Updating Steam’s download tool")
                ) {}
                ImportProgressRow(
                    title: "Northern Lights", poster: posters[2], state: .running(fraction: nil, detail: "Downloading from Steam")
                ) {}
                ImportProgressRow(
                    title: "Northern Lights",
                    poster: posters[2],
                    state: .failed(
                        message: "Steam would not give it to this account. "
                            + "Wallpaper Engine’s Workshop items download only for an account that owns Wallpaper Engine."
                    )
                )
                ImportProgressRow(title: "Rain on Glass", state: .failed(message: "Livepaper is not signed in to Steam.")) {} onRetry: {}
            }
            .frame(width: Layout.rowWidth)
        }
    }
}

private enum Layout {
    static let rowWidth: CGFloat = 520
}
