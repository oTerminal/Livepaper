import SwiftUI

/// A small text button: a compact capsule with the full 40 pt target, for a
/// secondary action in a line of controls (StatusLine's Restart, PanZoomEditor's
/// Reset, the popover's Choose on a display that shows nothing).
public struct CompactTextButton: View {
    @Accessibility private var accessibility
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    private let title: Text
    private let action: () -> Void

    public init(title: Text, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    public var body: some View {
        Button {
            // A key press on the focused button must not animate what the action changes.
            withoutAnimationIfKeyPress(action)
        } label: {
            title
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, Spacing.small + Spacing.hairline)
                .padding(.vertical, Spacing.hairline)
                .background(Color.primary.opacity(isHovered && isEnabled ? 0.14 : 0.08), in: .capsule)
                .contentShape(.focusEffect, .capsule)
                .overlay {
                    if accessibility.increaseContrast {
                        Capsule().strokeBorder(.secondary, lineWidth: 1)
                    }
                }
                .opacity(isEnabled ? 1 : 0.4)
                .frame(minWidth: Spacing.minimumHitArea, minHeight: Spacing.minimumHitArea)
                .contentShape(.rect)
        }
        .buttonStyle(.press)
        // The one way out of a degraded state never truncates; the message gives way instead.
        .fixedSize()
        .onHover { isHovered = $0 }
        .animation(
            accessibility.fade(isHovered ? Motion.enter(Motion.Duration.hover) : Motion.exit(Motion.Duration.hover)),
            value: isHovered
        )
    }
}
