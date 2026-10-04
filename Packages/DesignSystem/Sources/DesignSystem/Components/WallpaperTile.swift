import SwiftUI

/// A poster in the grid. After the pointer rests on it for 200 ms it shows the
/// live preview the caller hands in; the package never plays video itself.
/// Tiles are content, not the functional layer, so they are never glass.
public struct WallpaperTile<ID: Hashable, LivePreview: View>: View {
    @Environment(LivePreviewCoordinator.self) private var coordinator: LivePreviewCoordinator?
    @Accessibility private var accessibility
    @State private var isHovered = false

    private let id: ID
    private let poster: Image
    private let title: String
    private let isSelected: Bool
    private let isFavourite: Bool
    private let action: () -> Void
    private let livePreview: () -> LivePreview

    public init(
        id: ID,
        poster: Image,
        title: String,
        isSelected: Bool = false,
        isFavourite: Bool = false,
        action: @escaping () -> Void,
        @ViewBuilder livePreview: @escaping () -> LivePreview
    ) {
        self.id = id
        self.poster = poster
        self.title = title
        self.isSelected = isSelected
        self.isFavourite = isFavourite
        self.action = action
        self.livePreview = livePreview
    }

    private var isLive: Bool {
        coordinator?.live == AnyHashable(id)
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: Spacing.small) {
                picture
                Text(title)
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .padding(.horizontal, Spacing.tight)
            }
            // Selection never animates, even inside a caller's withAnimation.
            .animation(nil, value: isSelected)
            .contentShape(.rect)
            // The ring follows the poster, not the title. Set here, on the label
            // itself: a shape on the picture inside it is not the button's.
            .contentShape(.focusEffect, PosterFocusShape())
        }
        .buttonStyle(.press)
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                coordinator?.pointerEntered(AnyHashable(id))
            } else {
                coordinator?.pointerExited(AnyHashable(id))
            }
        }
        .onDisappear { coordinator?.pointerExited(AnyHashable(id)) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(isFavourite ? Text("Favourite", bundle: .module) : Text(verbatim: ""))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        // The element made above is not the button's, so it has no press of its own.
        .accessibilityAction { action() }
    }

    private var picture: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
        return Color.clear
            .aspectRatio(16 / 10, contentMode: .fit)
            .overlay {
                poster
                    .resizable()
                    .scaledToFill()
            }
            .overlay {
                // A crossfade in place, scoped to the preview alone; it leaves quicker than it came.
                ZStack {
                    if isLive {
                        livePreview()
                            .transition(.opacity)
                    }
                }
                .animation(
                    accessibility.fade(isLive ? Motion.enter(Motion.Duration.panel) : Motion.exit(Motion.Duration.panel)),
                    value: isLive
                )
            }
            .overlay(alignment: .topTrailing) {
                if isFavourite {
                    Image(systemName: "heart.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
                        .padding(Spacing.small)
                }
            }
            .clipShape(shape)
            .imageOutline(shape)
            .background { elevation(shape) }
            // Selection is state, so it is a border; elevation is a shadow.
            .overlay {
                RoundedRectangle(cornerRadius: Radius.outer(inner: Radius.tile, padding: SelectionRing.outset), style: .continuous)
                    .strokeBorder(Color.accentColor, lineWidth: SelectionRing.width)
                    .padding(-SelectionRing.outset)
                    .opacity(isSelected ? 1 : 0)
                    .animation(nil, value: isSelected)
            }
    }

    /// Two fixed shadows behind the poster. Hover fades the deeper one in, so
    /// only an opacity animates: a shadow whose radius animates is re-blurred on
    /// every frame, under a pointer that sweeps the grid constantly.
    private func elevation(_ shape: RoundedRectangle) -> some View {
        ZStack {
            shape.fill(.black).shadow(color: .black.opacity(0.12), radius: 4, y: 2)
            shape.fill(.black).shadow(color: .black.opacity(0.22), radius: 10, y: 5)
                .opacity(isHovered ? 1 : 0)
                .animation(
                    accessibility.fade(isHovered ? Motion.enter(Motion.Duration.hover) : Motion.exit(Motion.Duration.hover)),
                    value: isHovered
                )
        }
    }
}

/// The poster's rounded rectangle at the top of the tile, for the focus ring:
/// the poster is as wide as the tile and 16:10.
private struct PosterFocusShape: Shape {
    nonisolated func path(in rect: CGRect) -> Path {
        let poster = CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.width * 10 / 16)
        return RoundedRectangle(cornerRadius: Radius.tile, style: .continuous).path(in: poster)
    }
}

/// The accent ring around a selected tile: concentric with the tile, one gap out.
private nonisolated enum SelectionRing {
    static let gap: CGFloat = 2
    static let width: CGFloat = 3
    static let outset = gap + width
}
