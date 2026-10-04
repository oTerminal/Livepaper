import SwiftUI

/// One line of a `DetailsList`.
public nonisolated struct DetailsRow: Hashable, Sendable {
    public let label: String
    public let value: String
    /// A tooltip, and the VoiceOver hint.
    public let help: String?

    public init(label: String, value: String, help: String? = nil) {
        self.label = label
        self.value = value
        self.help = help
    }
}

/// Facts about a file in two columns: labels trailing, values leading. It sits
/// inside the inspector, so it has no surface of its own. VoiceOver reads each
/// row as one element ("Codec, HEVC"), not as two unrelated texts. An empty
/// list draws nothing.
public struct DetailsList: View {
    private let rows: [DetailsRow]

    public init(rows: [DetailsRow]) {
        self.rows = rows
    }

    public var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: Spacing.medium, verticalSpacing: Spacing.small) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    Text(row.label)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .gridColumnAlignment(.trailing)
                        .help(row.help ?? "")
                        // The value's element speaks for the whole row.
                        .accessibilityHidden(true)
                    Text(row.value)
                        .monospacedDigit()
                        // Paths keep both ends: the volume and the file name.
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(row.help ?? "")
                        .accessibilityElement(children: .ignore)
                        // One label, "Resolution, 3840 × 2160": VoiceOver speaks a
                        // value before the label, which would put the number first.
                        .accessibilityLabel(Text(verbatim: "\(row.label), \(row.value)"))
                        .accessibilityHint(row.help ?? "")
                }
            }
        }
        .font(.callout)
    }
}
