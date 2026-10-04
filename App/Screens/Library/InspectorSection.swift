import DesignSystem
import SwiftUI

/// A titled part of the inspector, with an optional line under the title. Plain
/// layout on the design system's spacing and the system's text styles; it adds
/// no value of its own.
struct InspectorSection<Content: View>: View {
    let title: String
    let caption: String?
    let content: Content

    init(_ title: String, caption: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.caption = caption
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            VStack(alignment: .leading, spacing: Spacing.hairline) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            content
        }
    }
}
