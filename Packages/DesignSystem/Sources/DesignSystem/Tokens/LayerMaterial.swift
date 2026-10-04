import SwiftUI

/// Which material each layer of the interface uses. Glass belongs to the
/// floating functional layer only; content and wallpaper tiles never get it.
public nonisolated enum LayerMaterial: CaseIterable, Sendable {
    /// The window's content area.
    case content
    /// A wallpaper tile. The poster is the surface.
    case tile
    case sidebar
    case toolbar
    case popover
    /// A control floating over the inspector's preview.
    case inspectorControl

    public enum Fill: Equatable, Sendable {
        /// No surface of its own.
        case none
        case windowBackground
        /// Liquid Glass.
        case glass
        /// The Reduce Transparency substitute for glass: opaque, with a defined edge.
        case opaqueRaised
    }

    public func fill(reduceTransparency: Bool) -> Fill {
        switch self {
        case .content: .windowBackground
        case .tile: .none
        case .sidebar, .toolbar, .popover, .inspectorControl: reduceTransparency ? .opaqueRaised : .glass
        }
    }
}

extension View {
    /// Gives the view the surface its layer calls for. Neighbouring glass
    /// surfaces must share a `GlassEffectContainer`; never put glass on glass.
    public func layerSurface(_ layer: LayerMaterial, in shape: some InsettableShape, isInteractive: Bool = false) -> some View {
        modifier(LayerSurface(layer: layer, shape: shape, isInteractive: isInteractive))
    }
}

private struct LayerSurface<S: InsettableShape>: ViewModifier {
    @Accessibility private var accessibility
    let layer: LayerMaterial
    let shape: S
    let isInteractive: Bool

    func body(content: Content) -> some View {
        switch layer.fill(reduceTransparency: accessibility.reduceTransparency) {
        case .none:
            content
        case .windowBackground:
            content.background(Color(nsColor: .windowBackgroundColor), in: shape)
        case .glass:
            content.glassEffect(isInteractive ? .regular.interactive() : .regular, in: shape)
        case .opaqueRaised:
            content
                .background(Color(nsColor: .controlBackgroundColor), in: shape)
                .overlay {
                    shape
                        .strokeBorder(.separator, lineWidth: accessibility.increaseContrast ? 2 : 1)
                        .allowsHitTesting(false)
                }
        }
    }
}
