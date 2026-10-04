import DesignSystem
import SwiftUI

/// One labelled state of a component. A page is a stack of these, so every
/// state is on screen at once.
struct StateSection<Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text(title)
                    .font(.headline)
                if let note {
                    Text(note)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            // An opaque plate, so the labels stay readable over the busy backdrop.
            .padding(Spacing.small)
            .background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: Radius.control))
            .padding(-Spacing.small)
            content
                .padding(.top, Spacing.tight)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, Spacing.extraLarge)
    }
}
