import CoreGraphics

/// Corner-radius tokens. Raw `cornerRadius:` literals outside this package are a
/// lint error.
///
/// Prefer `ConcentricRectangle` with `.containerShape`, which derives the radius
/// from the container. These values are for where that does not apply: the
/// outermost shape of a component, and shapes with no rounded container.
public nonisolated enum Radius {
    /// Buttons, fields, rows.
    public static let control: CGFloat = 8
    /// Wallpaper tiles and posters.
    public static let tile: CGFloat = 12
    /// Cards holding controls.
    public static let card: CGFloat = 16
    /// Popovers, toasts and other floating panels.
    public static let panel: CGFloat = 20

    /// The concentric rule: a shape that wraps another with `padding` between
    /// them. Past about 24 pt of padding the two read as separate surfaces, so
    /// choose each radius on its own instead.
    public static func outer(inner: CGFloat, padding: CGFloat) -> CGFloat {
        inner + padding
    }
}
