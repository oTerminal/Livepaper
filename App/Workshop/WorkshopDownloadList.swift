import DesignSystem
import LivepaperWorkshop
import SwiftUI

/// The Workshop items being got, one row each, as the import list shows its
/// imports: under the Workshop window's page and under the library's grid. A
/// row leaves once its item is handed to the import, whose own row takes over.
/// A waiting or running row can be cancelled; a failed one says why, offers
/// Retry where trying again or signing in would help, and can be taken off
/// the list from its menu.
struct WorkshopDownloadList: View {
    @Environment(WorkshopModel.self) private var workshop

    var body: some View {
        if !workshop.downloads.rows.isEmpty {
            ViewThatFits(in: .vertical) {
                rows
                ScrollView { rows }
            }
            .frame(maxHeight: Layout.maxHeight)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Workshop Downloads")
        }
    }

    private var rows: some View {
        VStack(spacing: Spacing.small) {
            ForEach(workshop.downloads.rows) { row in
                WorkshopDownloadRow(row: row)
            }
        }
        .padding(.horizontal, Spacing.extraLarge)
        .padding(.vertical, Spacing.medium)
    }
}

private struct WorkshopDownloadRow: View {
    @Environment(AppModel.self) private var model
    @Environment(WorkshopModel.self) private var workshop
    let row: WorkshopDownloads.Row

    var body: some View {
        ImportProgressRow(
            title: row.title,
            poster: poster,
            state: state,
            onCancel: canCancel ? { workshop.cancel(row.item) } : nil,
            onRetry: canRetry ? { workshop.retry(row.item) } : nil
        )
        .contextMenu {
            if case .failed = row.state {
                Button("Remove from List") { workshop.cancel(row.item) }
            }
        }
    }

    /// The item's preview from its page, once fetched.
    private var poster: Image? {
        workshop.previews[row.item].flatMap { model.art.picture(at: $0, size: Layout.poster) }
    }

    private var state: ImportProgressState {
        switch row.state {
        case .waiting:
            .queued
        case .settingUp(let percent):
            .running(fraction: Double(percent) / 100, detail: workshopStageWords(row.state) ?? "")
        case .starting, .signingIn, .downloading, .opening:
            .running(fraction: nil, detail: workshopStageWords(row.state) ?? "")
        case .failed(let problem):
            .failed(message: problem.words + ".")
        }
    }

    private var canCancel: Bool {
        if case .failed = row.state { false } else { true }
    }

    private var canRetry: Bool {
        if case .failed(let problem) = row.state { problem.canRetry || problem.needsSignIn } else { false }
    }
}

private nonisolated enum Layout {
    /// Three rows and the start of a fourth, as the import list.
    static let maxHeight: CGFloat = 200
    /// The size `ImportProgressRow` draws a row's poster at.
    static let poster = CGSize(width: 64, height: 40)
}
