import SwiftUI

/// A symbol and words with a 40 pt target, for a line of controls on a popover
/// or card, such as the popover's Pause All. The symbol has a fixed slot, so
/// the words do not move when the caller swaps it (Pause All for Resume All).
public struct LabelButton: View {
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
            SymbolLabel(title: title, systemImage: systemImage, isOn: false)
        }
        .buttonStyle(.press)
        .accessibilityLabel(Text(verbatim: title))
    }
}

/// `LabelButton` as a toggle, such as the popover's Mute: the words stay, the
/// caller swaps the symbol, and on is a pill of `primary` behind both, as
/// FitModePicker marks its selection. Not the accent: a popover never makes the
/// app active, and there the accent draws grey and reads as disabled.
public struct LabelToggle: View {
    private let title: String
    private let systemImage: String
    @Binding private var isOn: Bool

    public init(_ title: String, systemImage: String, isOn: Binding<Bool>) {
        self.title = title
        self.systemImage = systemImage
        _isOn = isOn
    }

    public var body: some View {
        Button {
            withoutAnimationIfKeyPress { isOn.toggle() }
        } label: {
            SymbolLabel(title: title, systemImage: systemImage, isOn: isOn)
        }
        .buttonStyle(.press)
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? Text("On", bundle: .module) : Text("Off", bundle: .module))
    }
}

/// What both draw: the symbol in its slot, the words, and the on pill.
private struct SymbolLabel: View {
    @Accessibility private var accessibility
    @Environment(\.isEnabled) private var isEnabled
    let title: String
    let systemImage: String
    let isOn: Bool

    var body: some View {
        Label {
            Text(verbatim: title)
        } icon: {
            Image(systemName: systemImage)
                .frame(width: Metrics.symbolSlot)
        }
        .font(.callout)
        .opacity(isEnabled ? 1 : Metrics.disabledOpacity)
        // The symbol's side sits 2 pt closer to the edge than the words' side.
        .padding(.leading, Spacing.small - Spacing.hairline)
        .padding(.trailing, Spacing.small)
        .padding(.vertical, Spacing.tight)
        .background {
            Capsule()
                .fill(Pill.fill(increaseContrast: accessibility.increaseContrast))
                .opacity(isOn ? 1 : 0)
                // State, not motion: a caller's `withAnimation` must not fade it.
                .animation(nil, value: isOn)
        }
        .contentShape(.focusEffect, .capsule)
        .frame(minHeight: Spacing.minimumHitArea)
        .contentShape(.rect)
    }
}

private nonisolated enum Metrics {
    /// Fits the widest symbol these carry at callout size, the speaker with its waves.
    static let symbolSlot: CGFloat = 20
    static let disabledOpacity = 0.4
}
