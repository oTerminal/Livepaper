import DesignSystem
import SwiftUI

struct ImportProgressRowPage: View {
    @State private var fraction = 0.42
    @State private var live = ImportProgressState.running(fraction: 0.42, detail: "Optimising")
    private let posters = (0..<4).map { SamplePicture.image(seed: $0 + 40) }

    var body: some View {
        StateSection(title: "Live", note: "Drag the slider: the percentage changes in place and nothing beside it moves.") {
            ImportProgressRow(title: "Harbour at Dusk.mov", poster: posters[0], state: live) {
                live = .failed(message: "Import cancelled.")
            } onRetry: {
                live = .running(fraction: fraction, detail: "Optimising")
            }
            .frame(width: Layout.rowWidth)
            HStack {
                Slider(value: $fraction, in: 0...1)
                    .frame(width: 200)
                Button("Finish") { live = .finished }
                Button("Fail") { live = .failed(message: "The file could not be read.") }
                Button("Queue") { live = .queued }
            }
            .onChange(of: fraction) { _, fraction in
                live = .running(fraction: fraction, detail: "Optimising")
            }
        }

        StateSection(title: "All states", note: "Every row is the same height, with the same columns.") {
            VStack(spacing: Spacing.medium) {
                ImportProgressRow(title: "Queued", state: .queued) {}
                ImportProgressRow(title: "Running, 0%", poster: posters[1], state: .running(fraction: 0, detail: "Copying")) {}
                ImportProgressRow(title: "Running, 42%", poster: posters[2], state: .running(fraction: 0.42, detail: "Optimising")) {}
                ImportProgressRow(title: "Indeterminate", poster: posters[3], state: .running(fraction: nil, detail: "Reading")) {}
                ImportProgressRow(title: "Finished", poster: posters[0], state: .finished)
                ImportProgressRow(
                    title: "Failed",
                    poster: posters[1],
                    state: .failed(message: "This video uses a codec that macOS cannot play.")
                ) {} onRetry: {}
                ImportProgressRow(
                    title: "A very long file name that was exported from somewhere with no regard for anyone - final v2 (1).mov",
                    poster: posters[2],
                    state: .running(fraction: 1, detail: "A long detail string that also has to give way to the percentage")
                ) {}
            }
            .frame(width: Layout.rowWidth)
        }

        StateSection(title: "No actions", note: "Without onCancel or onRetry the trailing slot stays, empty, so the columns hold.") {
            VStack(spacing: Spacing.medium) {
                ImportProgressRow(title: "Running", state: .running(fraction: 0.7, detail: "Optimising"))
                ImportProgressRow(title: "Failed", state: .failed(message: "The file could not be read."))
            }
            .frame(width: Layout.rowWidth)
        }
    }
}

private enum Layout {
    static let rowWidth: CGFloat = 420
}
