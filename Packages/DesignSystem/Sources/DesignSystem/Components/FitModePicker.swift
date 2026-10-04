import SwiftUI

/// One segment of a `FitModePicker`.
public nonisolated struct FitModeOption<Value: Hashable>: Identifiable {
    public let value: Value
    public let title: String
    public let systemImage: String

    public var id: Value { value }

    public init(value: Value, title: String, systemImage: String) {
        self.value = value
        self.title = title
        self.systemImage = systemImage
    }
}

extension FitModeOption: Sendable where Value: Sendable {}

/// A segmented control for the inspector, floating over the preview: one glass
/// capsule, with a plain selection pill inside it (never glass on glass).
///
/// The pill slides when a segment is clicked and jumps when the arrow keys move
/// it. It moves by `offset`, never by frame. With Reduce Motion it crossfades
/// between segments instead of sliding.
public struct FitModePicker<Value: Hashable>: View {
    @Accessibility private var accessibility
    @State private var hadSelection = false
    @Environment(\.isEnabled) private var isEnabled

    @Binding private var selection: Value
    private let options: [FitModeOption<Value>]
    private let label: String

    public init(_ label: String, selection: Binding<Value>, options: [FitModeOption<Value>]) {
        self.label = label
        _selection = selection
        self.options = options
    }

    private var selectedIndex: Int? {
        options.firstIndex { $0.value == selection }
    }

    public var body: some View {
        EqualWidthRow {
            ForEach(options) { option in
                segment(option)
            }
        }
        .padding(.horizontal, Metrics.inset)
        .background {
            slidingPill
                .padding(Metrics.inset)
        }
        .opacity(isEnabled ? 1 : Metrics.disabledOpacity)
        .layerSurface(.inspectorControl, in: Capsule())
        // One tab stop for the whole control, like a native segmented control;
        // the arrow keys move the selection.
        .focusable()
        .contentShape(.focusEffect, Capsule())
        .onMoveCommand(perform: move)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private func segment(_ option: FitModeOption<Value>) -> some View {
        let isSelected = option.value == selection
        return Button {
            selection = option.value
        } label: {
            HStack(spacing: Spacing.tight) {
                Image(systemName: option.systemImage)
                Text(option.title)
                    .lineLimit(1)
            }
            .font(.callout)
            .foregroundStyle(isSelected ? .primary : .secondary)
            // The colour changes over the pill's travel, not the instant of the click.
            .animation(accessibility.animation(Motion.Spring.ui), value: isSelected)
            .padding(.horizontal, Spacing.medium)
            .frame(maxWidth: .infinity, minHeight: Spacing.minimumHitArea - 2 * Metrics.inset)
            .background {
                // Reduce Motion: the pill fades out here and in there.
                Capsule()
                    .fill(pillFill)
                    .opacity(accessibility.reduceMotion && isSelected ? 1 : 0)
                    .animation(accessibility.animation(Motion.Spring.ui), value: isSelected)
            }
            // The hit area runs the full height of the capsule.
            .padding(.vertical, Metrics.inset)
            .frame(minWidth: Spacing.minimumHitArea)
            .contentShape(.rect)
        }
        .buttonStyle(.press)
        // Focus belongs to the whole control; see `body`.
        .focusable(false)
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var slidingPill: some View {
        GeometryReader { proxy in
            let width = proxy.size.width / CGFloat(max(options.count, 1))
            Capsule()
                .fill(pillFill)
                .frame(width: width)
                .offset(x: width * CGFloat(selectedIndex ?? 0))
                // Key presses go through `withoutAnimation`, which switches this off.
                // A first selection appears in place: it has nowhere to slide from.
                .animation(hadSelection ? accessibility.animation(Motion.Spring.ui) : nil, value: selectedIndex)
        }
        .opacity(accessibility.reduceMotion || selectedIndex == nil ? 0 : 1)
        .allowsHitTesting(false)
        .onChange(of: selectedIndex, initial: true) { _, index in
            hadSelection = index != nil
        }
    }

    private var pillFill: Color {
        Pill.fill(increaseContrast: accessibility.increaseContrast)
    }

    private func move(_ direction: MoveCommandDirection) {
        guard isEnabled else { return }
        let target: Int
        switch (direction, selectedIndex) {
        case (.left, let index?): target = index - 1
        case (.right, let index?): target = index + 1
        // With nothing selected yet, either arrow picks the first option.
        case (.left, nil), (.right, nil): target = 0
        default: return
        }
        guard options.indices.contains(target) else { return }
        withoutAnimation {
            selection = options[target].value
        }
    }
}

/// Lays its children out side by side, all as wide as the widest, so the pill
/// can move in equal steps.
private struct EqualWidthRow: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let natural = (sizes.map(\.width).max() ?? 0) * CGFloat(subviews.count)
        return CGSize(
            width: min(natural, proposal.width ?? natural),
            height: sizes.map(\.height).max() ?? 0
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard !subviews.isEmpty else { return }
        let width = bounds.width / CGFloat(subviews.count)
        for (index, subview) in subviews.enumerated() {
            subview.place(
                at: CGPoint(x: bounds.minX + width * CGFloat(index), y: bounds.minY),
                proposal: ProposedViewSize(width: width, height: bounds.height)
            )
        }
    }
}

private nonisolated enum Metrics {
    /// The gap between the pill and the capsule around it. Both are capsules,
    /// so they stay concentric at any inset.
    static let inset = Spacing.tight
    static let disabledOpacity = 0.4
}
