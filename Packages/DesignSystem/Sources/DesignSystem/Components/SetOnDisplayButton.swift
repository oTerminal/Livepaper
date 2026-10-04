import SwiftUI

/// Somewhere a `SetOnDisplayButton` can set the wallpaper.
public nonisolated struct SetOnDisplayTarget: Identifiable, Hashable, Sendable {
    /// Passed to the action when the user chooses "All Displays".
    public static let allID = "DesignSystem.SetOnDisplayTarget.all"

    public let id: String
    public let name: String
    /// Already showing this wallpaper: checked in the menu.
    public let isCurrent: Bool

    public init(id: String, name: String, isCurrent: Bool = false) {
        self.id = id
        self.name = name
        self.isCurrent = isCurrent
    }
}

public nonisolated enum SetOnDisplayState: Hashable, Sendable {
    case idle
    case working
    case done
}

/// The inspector's primary action. With one target it is a button; with
/// several, the button sets on the first and a menu segment offers the rest
/// and "All Displays". The icon, the spinner and the checkmark share one fixed
/// slot, so the title never moves between states.
public struct SetOnDisplayButton: View {
    @Accessibility private var accessibility

    private let targets: [SetOnDisplayTarget]
    private let state: SetOnDisplayState
    private let action: (SetOnDisplayTarget.ID) -> Void

    public init(
        targets: [SetOnDisplayTarget],
        state: SetOnDisplayState = .idle,
        action: @escaping (SetOnDisplayTarget.ID) -> Void
    ) {
        self.targets = targets
        self.state = state
        self.action = action
    }

    public var body: some View {
        control
            .buttonStyle(.glassProminent)
            // The inspector's one primary action, and its chevron sits 2 pt away:
            // both need a full-size target.
            .controlSize(.extraLarge)
            .disabled(state == .working || targets.isEmpty)
    }

    /// A native split `Menu` drops the glass style and cannot show the spinner,
    /// so the two halves are separate controls sharing one glass container.
    private var control: some View {
        GlassEffectContainer(spacing: Spacing.hairline) {
            HStack(spacing: Spacing.hairline) {
                Button {
                    // A key press on the focused button must not animate the state it starts.
                    withoutAnimationIfKeyPress {
                        if let first = targets.first {
                            action(first.id)
                        }
                    }
                } label: {
                    label(for: targets.first)
                }
                .accessibilityValue(stateDescription)
                if targets.count > 1 {
                    Menu {
                        ForEach(targets) { target in
                            Button {
                                withoutAnimationIfKeyPress { action(target.id) }
                            } label: {
                                if target.isCurrent {
                                    Label(target.name, systemImage: "checkmark")
                                } else {
                                    Text(verbatim: target.name)
                                }
                            }
                        }
                        Divider()
                        Button {
                            withoutAnimationIfKeyPress { action(SetOnDisplayTarget.allID) }
                        } label: {
                            Text("All Displays", bundle: .module)
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                            .frame(minWidth: Metrics.chevronSlot, minHeight: Metrics.iconSlot)
                    }
                    .menuStyle(.button)
                    .menuIndicator(.hidden)
                    .accessibilityLabel(Text("Choose Display", bundle: .module))
                }
            }
            // Hugs its content, but a long display name truncates rather than overflows.
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func label(for target: SetOnDisplayTarget?) -> some View {
        HStack(spacing: Spacing.small) {
            iconSlot
            if let target {
                Text("Set on \(target.name)", bundle: .module)
            } else {
                Text("Set on Display", bundle: .module)
            }
        }
        .lineLimit(1)
        // Icon-side padding is text-side padding less 2 pt.
        .padding(.leading, -Spacing.hairline)
    }

    private var iconSlot: some View {
        ZStack {
            // Always present, so idle to done is a symbol replace, not an insertion.
            Image(systemName: state == .done ? "checkmark" : "display")
                .contentTransition(accessibility.symbolReplace)
                .opacity(state == .working ? 0 : 1)
            if state == .working {
                ProgressView()
                    .controlSize(.small)
                    .transition(.opacity)
            }
        }
        .frame(width: Metrics.iconSlot, height: Metrics.iconSlot)
        .animation(accessibility.fade(Motion.enter(Motion.Duration.hover)), value: state)
        .accessibilityHidden(true)
    }

    private var stateDescription: Text {
        switch state {
        case .idle: Text(verbatim: "")
        case .working: Text("Setting", bundle: .module)
        case .done: Text("Done", bundle: .module)
        }
    }
}

private nonisolated enum Metrics {
    /// A small `ProgressView` is 16 pt; the symbols fit the same square.
    static let iconSlot: CGFloat = 16
    /// With the button's own padding, a chevron segment at least the minimum hit area wide.
    static let chevronSlot: CGFloat = 16
}
