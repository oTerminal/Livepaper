import SwiftUI

/// Where a `TransportCluster` sits, which decides whether it brings its own surface.
public nonisolated enum TransportClusterStyle: Sendable {
    /// Inside a card or popover, which already is the surface.
    case plain
    /// Floating over content, on one glass capsule.
    case glass
}

/// Previous, play or pause, next. In `.glass` style the three buttons share one
/// capsule: three glass circles side by side would be glass next to glass with
/// no container. Never use `.glass` inside a popover or card, which would put
/// glass on glass; that is what `.plain` is for.
public struct TransportCluster: View {
    @Accessibility private var accessibility

    private let isPlaying: Bool
    private let style: TransportClusterStyle
    private let canSkip: Bool
    private let onPrevious: () -> Void
    private let onPlayPause: () -> Void
    private let onNext: () -> Void

    public init(
        isPlaying: Bool,
        style: TransportClusterStyle = .plain,
        canSkip: Bool = true,
        onPrevious: @escaping () -> Void,
        onPlayPause: @escaping () -> Void,
        onNext: @escaping () -> Void
    ) {
        self.isPlaying = isPlaying
        self.style = style
        self.canSkip = canSkip
        self.onPrevious = onPrevious
        self.onPlayPause = onPlayPause
        self.onNext = onNext
    }

    public var body: some View {
        switch style {
        case .plain:
            buttons
        case .glass:
            buttons
                .padding(Spacing.tight)
                .layerSurface(.inspectorControl, in: .capsule)
        }
    }

    private var buttons: some View {
        HStack(spacing: 0) {
            TransportButton(label: Text("Previous Wallpaper", bundle: .module), action: onPrevious) {
                Image(systemName: "backward.fill")
            }
            .disabled(!canSkip)

            TransportButton(
                label: isPlaying ? Text("Pause", bundle: .module) : Text("Play", bundle: .module),
                action: onPlayPause
            ) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3)
                    .contentTransition(accessibility.symbolReplace)
                    // The triangle's visual mass sits left of its bounding box.
                    .offset(x: isPlaying ? 0 : Metrics.playNudge)
                    .animation(accessibility.animation(Motion.Spring.ui), value: isPlaying)
            }

            TransportButton(label: Text("Next Wallpaper", bundle: .module), action: onNext) {
                Image(systemName: "forward.fill")
            }
            .disabled(!canSkip)
        }
    }
}

private struct TransportButton<Symbol: View>: View {
    @Environment(\.isEnabled) private var isEnabled
    @Accessibility private var accessibility
    @State private var isHovered = false

    let label: Text
    let action: () -> Void
    @ViewBuilder let symbol: Symbol

    var body: some View {
        Button {
            // Space or Return on the focused button must not animate the swap.
            withoutAnimationIfKeyPress(action)
        } label: {
            symbol
                .foregroundStyle(.primary)
                .opacity(isEnabled ? 1 : Metrics.disabledOpacity)
                .frame(minWidth: Spacing.minimumHitArea, minHeight: Spacing.minimumHitArea)
                .background {
                    Circle()
                        .fill(.primary.opacity(Metrics.hoverFillOpacity))
                        .opacity(isHovered && isEnabled ? 1 : 0)
                        .animation(
                            accessibility.fade(isHovered ? Motion.enter(Motion.Duration.hover) : Motion.exit(Motion.Duration.hover)),
                            value: isHovered
                        )
                }
                .contentShape([.interaction, .focusEffect], .circle)
        }
        .buttonStyle(.press)
        .onHover { isHovered = $0 }
        .accessibilityLabel(label)
        .help(label)
    }
}

private nonisolated enum Metrics {
    /// Half a hairline: enough to centre the play triangle's mass, not enough to see it move.
    static let playNudge = Spacing.hairline / 2
    static let disabledOpacity = 0.35
    static let hoverFillOpacity = 0.1
}
