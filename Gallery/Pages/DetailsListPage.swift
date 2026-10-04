import DesignSystem
import SwiftUI

struct DetailsListPage: View {
    private let file = [
        DetailsRow(label: "Resolution", value: "3840 × 2160"),
        DetailsRow(label: "Frame rate", value: "60 fps"),
        DetailsRow(label: "Duration", value: "0:24"),
        DetailsRow(label: "Codec", value: "HEVC", help: "High Efficiency Video Coding, decoded in hardware on this Mac"),
        DetailsRow(label: "Size", value: "182 MB"),
        DetailsRow(
            label: "Where",
            value: "/Users/sam/Library/Application Support/Livepaper/Library/Imported/2026/Harbour at Dusk (4K, 60 fps, colour graded).mov"
        ),
    ]

    var body: some View {
        StateSection(
            title: "File details",
            note: """
            Labels trail, values lead, digits are monospaced, values can be selected. The path wraps to two lines, then \
            truncates in the middle. Codec has a tooltip.
            """
        ) {
            DetailsList(rows: file)
                .frame(width: 300, alignment: .leading)
        }

        StateSection(title: "Empty", note: "Draws nothing: the box below is the Gallery's, to show where it would be.") {
            DetailsList(rows: [])
                .frame(width: 300, height: Spacing.section)
                .background(.quinary, in: .rect(cornerRadius: Radius.control))
        }

        StateSection(title: "Single row") {
            DetailsList(rows: [DetailsRow(label: "Duration", value: "0:24")])
        }
    }
}
