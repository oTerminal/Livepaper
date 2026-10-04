import DesignSystem
import LivepaperCore
import LivepaperImport
import SwiftUI

/// The imports under the grid, one row per candidate, in the order they run.
/// A waiting or running row can be cancelled; a failed row that Retry can help
/// offers it, and can be taken off the list from its menu. Finished rows, and
/// failed ones Retry cannot help, leave by themselves (`ImportList.tick`).
struct ImportListView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        // As tall as its rows, up to a few; past that it scrolls.
        ViewThatFits(in: .vertical) {
            rows
            ScrollView { rows }
        }
        .frame(maxHeight: Layout.maxHeight)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Imports")
    }

    private var rows: some View {
        VStack(spacing: Spacing.small) {
            ForEach(model.importList.rows) { row in
                ImportListRow(row: row)
            }
        }
        .padding(.horizontal, Spacing.extraLarge)
        .padding(.vertical, Spacing.medium)
    }
}

struct ImportListRow: View {
    @Environment(AppModel.self) private var model
    let row: ImportList.Row

    var body: some View {
        let state = row.state
        ImportProgressRow(
            title: row.candidate.name,
            poster: poster,
            state: state.importProgressState,
            onCancel: state.canCancel ? { model.cancelImport(row.id) } : nil,
            onRetry: state.canRetry ? { model.retryImport(row.id) } : nil
        )
        .contextMenu {
            if state.canRemove {
                Button("Remove from List") { model.cancelImport(row.id) }
            }
        }
    }

    /// The wallpaper it made or already was; before that, a Wallpaper Engine item's own preview.
    private var poster: Image? {
        if let wallpaper = row.state.wallpaper {
            model.art.poster(for: wallpaper, size: Layout.poster)
        } else if let preview = row.candidate.preview {
            model.art.picture(at: preview, size: Layout.poster)
        } else {
            nil
        }
    }
}

private nonisolated enum Layout {
    /// Three rows and the start of a fourth, so the list says there is more.
    static let maxHeight: CGFloat = 200
    /// The size `ImportProgressRow` draws a row's poster at, which it is decoded to cover.
    static let poster = CGSize(width: 64, height: 40)
}

#Preview("Import list, every row state") {
    // Finished (here a duplicate), failed with Retry, running and waiting, as the list makes them.
    let model = AppModel.preview()
    var list = ImportList()
    let ids = (0..<4).map { _ in UUID() }
    let names = ["Harbour at Dusk", "Unreadable fail", "Harbour at Night", "Paper Boats"]
    _ = list.enqueue(names.map { ImportCandidate(source: URL(filePath: "/tmp/\($0).mov"), name: $0) }, ids: ids)
    _ = list.received(.finished(.duplicate(of: model.library.wallpapers[0])), for: ids[0], at: .now)
    _ = list.failed(ids[1], error: MediaError.readFailed("preview"), at: .now)
    _ = list.received(.progress(ImportProgress(stage: .normalise, fraction: 0.42)), for: ids[2], at: .now)
    model.importList = list
    return ImportListView()
        .frame(width: 560)
        .environment(model)
}
