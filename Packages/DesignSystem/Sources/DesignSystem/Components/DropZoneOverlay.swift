import SwiftUI

/// Covers the window while files are dragged over it. It never takes part in
/// hit testing, so the drop still reaches the view underneath: attach the drop
/// destination to the content, not to this overlay.
public struct DropZoneOverlay: View {
    @Accessibility private var accessibility

    private let isTargeted: Bool
    private let title: String
    private let message: String?

    public init(isTargeted: Bool, title: String, message: String? = nil) {
        self.isTargeted = isTargeted
        self.title = title
        self.message = message
    }

    public var body: some View {
        ZStack {
            if isTargeted {
                Color.black
                    .opacity(accessibility.increaseContrast ? Metrics.scrimOpacityHighContrast : Metrics.scrimOpacity)
                    .transition(.opacity)

                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(
                        Color.accentColor,
                        style: StrokeStyle(
                            lineWidth: accessibility.increaseContrast ? 3 : 2,
                            lineCap: .round,
                            dash: Metrics.dash
                        )
                    )
                    .padding(Spacing.medium)
                    .transition(.opacity)

                plate
                    // Centred like a modal: it has no trigger to grow from.
                    .transition(
                        accessibility.reduceMotion
                            ? .opacity
                            : .scale(scale: Metrics.entranceScale, anchor: .center).combined(with: .opacity)
                    )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(
            accessibility.animation(isTargeted ? Motion.enter(Motion.Duration.popover) : Motion.exit(Motion.Duration.popover)),
            value: isTargeted
        )
        .allowsHitTesting(false)
        .onChange(of: isTargeted) { _, targeted in
            // A drag moves no focus, so VoiceOver would otherwise never hear about it.
            if targeted {
                AccessibilityNotification.Announcement(title).post()
            }
        }
    }

    private var plate: some View {
        VStack(spacing: Spacing.small) {
            Image(systemName: "square.and.arrow.down")
                // Carries the weight of the semibold title beneath it.
                .font(.largeTitle.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.bottom, Spacing.tight)
            Text(title)
                .font(.title3.weight(.semibold))
            if let message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Spacing.section)
        .padding(.vertical, Spacing.extraLarge)
        .frame(maxWidth: Metrics.plateMaxWidth)
        .layerSurface(.popover, in: RoundedRectangle(cornerRadius: Radius.panel, style: .continuous))
        // The same elevation as the popover: one floating layer, one shadow.
        .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
        .padding(Spacing.section)
        .accessibilityElement(children: .ignore)
        // Title first, then the message, as one label: VoiceOver speaks a value before the label.
        .accessibilityLabel(Text(verbatim: message.map { "\(title). \($0)" } ?? title))
    }
}

extension View {
    /// Lays a `DropZoneOverlay` over the view. The view keeps its own drop destination.
    public func dropZoneOverlay(isTargeted: Bool, title: String, message: String? = nil) -> some View {
        overlay {
            DropZoneOverlay(isTargeted: isTargeted, title: title, message: message)
        }
    }
}

private nonisolated enum Metrics {
    /// The nearest token to the 0.96 every scaled entrance starts from.
    static let entranceScale = Motion.enterScale
    static let scrimOpacity = 0.3
    static let scrimOpacityHighContrast = 0.5
    /// Dash and gap of the border, in points.
    static let dash: [CGFloat] = [10, 8]
    /// Keeps the message to a comfortable measure in a wide window.
    static let plateMaxWidth: CGFloat = 360
}
