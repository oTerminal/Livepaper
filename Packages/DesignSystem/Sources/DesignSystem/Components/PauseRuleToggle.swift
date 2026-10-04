import SwiftUI

/// One pause rule in Settings: a symbol, a title, what the rule does, and a
/// switch. The whole row is the switch's label, so clicking the words flips it,
/// and VoiceOver reads "title, on, switch" with the detail and note as its hint.
/// A rule that is not available shows as off and disabled without changing the
/// stored value.
public struct PauseRuleToggle: View {
    @Accessibility private var accessibility
    private let title: String
    private let detail: String?
    private let systemImage: String
    @Binding private var isOn: Bool
    private let note: String?
    private let isAvailable: Bool

    public init(
        title: String,
        detail: String? = nil,
        systemImage: String,
        isOn: Binding<Bool>,
        note: String? = nil,
        isAvailable: Bool = true
    ) {
        self.title = title
        self.detail = detail
        self.systemImage = systemImage
        _isOn = isOn
        self.note = note
        self.isAvailable = isAvailable
    }

    public var body: some View {
        Toggle(isOn: Binding(get: { isAvailable && isOn }, set: { isOn = $0 })) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    // A fixed slot: symbols differ in width, titles must still line up across rows.
                    .frame(width: Metrics.symbolSlot)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.hairline) {
                    Text(title)
                    if let detail {
                        Text(detail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    if let note {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, minHeight: Spacing.minimumHitArea, alignment: .leading)
            .contentShape(.rect)
            // A macOS switch does not take clicks on its label by itself. Animated,
            // so the thumb slides as it does when the switch itself is clicked.
            .onTapGesture {
                withAnimation(accessibility.animation(Motion.Spring.ui)) { isOn.toggle() }
            }
            // The switch says all of it; read here too, the words would come twice.
            .accessibilityHidden(true)
        }
        .toggleStyle(.switch)
        .disabled(!isAvailable)
        // Named here: from this label the switch took no name at all. Settings'
        // accessibility tree found the four by role alone; Open at Login's, named so, had one.
        .accessibilityLabel(Text(verbatim: title))
        .accessibilityHint(Text(verbatim: [detail, note].compactMap { $0 }.joined(separator: "\n")))
    }
}

private nonisolated enum Metrics {
    /// Fits the widest symbol the rules use at body size.
    static let symbolSlot: CGFloat = 24
}
