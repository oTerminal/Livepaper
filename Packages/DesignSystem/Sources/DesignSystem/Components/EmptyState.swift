import SwiftUI

/// What a screen shows when it has nothing: a symbol, a title, a sentence, and
/// at most two ways out. It sits in the content layer, so it is never glass,
/// and it does not animate in: it appears on navigation, which is frequent.
public struct EmptyState: View {
    private let title: String
    private let message: String?
    private let systemImage: String
    private let actionTitle: String?
    private let action: (() -> Void)?
    private let secondaryActionTitle: String?
    private let secondaryAction: (() -> Void)?

    public init(
        title: String,
        message: String? = nil,
        systemImage: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil,
        secondaryActionTitle: String? = nil,
        secondaryAction: (() -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.actionTitle = actionTitle
        self.action = action
        self.secondaryActionTitle = secondaryActionTitle
        self.secondaryAction = secondaryAction
    }

    public var body: some View {
        VStack(spacing: Spacing.large) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.hierarchical)
                .font(.largeTitle)
                .imageScale(.large)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(spacing: Spacing.tight) {
                Text(title)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                if let message {
                    Text(message)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(maxWidth: Metrics.textWidth)

            buttons
        }
        .padding(Spacing.extraLarge)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder private var buttons: some View {
        let primary = actionTitle.flatMap { title in action.map { (title, $0) } }
        let secondary = secondaryActionTitle.flatMap { title in secondaryAction.map { (title, $0) } }
        if primary != nil || secondary != nil {
            // No spacing: the link's own 40 pt target supplies the gap, and the two never overlap.
            VStack(spacing: 0) {
                if let (title, action) = primary {
                    // A key press on either button must not animate what its action changes.
                    Button(title) { withoutAnimationIfKeyPress(action) }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
                if let (title, action) = secondary {
                    Button {
                        withoutAnimationIfKeyPress(action)
                    } label: {
                        Text(title)
                            .frame(minWidth: Spacing.minimumHitArea, minHeight: Spacing.minimumHitArea)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.link)
                }
            }
            .padding(.top, Spacing.tight)
        }
    }
}

private nonisolated enum Metrics {
    /// Keeps the message to short, centred lines (about 45 characters).
    static let textWidth: CGFloat = 320
}
