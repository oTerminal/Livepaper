import SwiftUI

/// A symbol alone in a 40 pt square, for a line of controls on a popover or
/// card, such as the popover's Open Library and Settings. The title is the
/// tooltip and what VoiceOver reads, since nothing on screen says it.
public struct SymbolButton: View {
    @Environment(\.isEnabled) private var isEnabled
    private let title: String
    private let systemImage: String
    private let action: () -> Void

    public init(_ title: String, systemImage: String, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.action = action
    }

    public var body: some View {
        Button {
            // A key press on the focused button must not animate what the action changes.
            withoutAnimationIfKeyPress(action)
        } label: {
            Image(systemName: systemImage)
                .font(.body)
                .opacity(isEnabled ? 1 : Metrics.disabledOpacity)
                .frame(width: Spacing.minimumHitArea, height: Spacing.minimumHitArea)
                .contentShape(.rect)
                // A glyph has no drawn edge of its own: the ring is a circle round
                // it, as TransportCluster's are, not the 40 pt square.
                .contentShape(.focusEffect, .circle)
        }
        .buttonStyle(.press)
        .accessibilityLabel(Text(verbatim: title))
        .help(Text(verbatim: title))
    }
}

private nonisolated enum Metrics {
    static let disabledOpacity = 0.4
}
