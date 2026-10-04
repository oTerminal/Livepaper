import SwiftUI

/// The heart that marks a favourite, such as beside a wallpaper's name in the
/// inspector: an outline in `secondary` when off, filled in the accent when on,
/// as a sidebar row marks its selection. No motion of its own: it is state.
public struct FavouriteToggle: View {
    @Environment(\.isEnabled) private var isEnabled
    @Binding private var isOn: Bool

    public init(isOn: Binding<Bool>) {
        _isOn = isOn
    }

    public var body: some View {
        Button {
            withoutAnimationIfKeyPress { isOn.toggle() }
        } label: {
            Image(systemName: "heart")
                .symbolVariant(isOn ? .fill : .none)
                .foregroundStyle(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
                .font(.title3)
                .opacity(isEnabled ? 1 : Metrics.disabledOpacity)
                // Even if the caller changes it inside `withAnimation`.
                .animation(nil, value: isOn)
                .frame(minWidth: Spacing.minimumHitArea, minHeight: Spacing.minimumHitArea)
                .contentShape(.rect)
                .contentShape(.focusEffect, .circle)
        }
        .buttonStyle(.press)
        .help(isOn ? Text("Unfavourite", bundle: .module) : Text("Favourite", bundle: .module))
        .accessibilityLabel(Text("Favourite", bundle: .module))
        .accessibilityAddTraits(.isToggle)
        .accessibilityValue(isOn ? Text("On", bundle: .module) : Text("Off", bundle: .module))
    }
}

private nonisolated enum Metrics {
    static let disabledOpacity = 0.4
}
