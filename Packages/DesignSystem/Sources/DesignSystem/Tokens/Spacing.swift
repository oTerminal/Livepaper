import CoreGraphics

/// The spacing scale used by every stack and padding: a 4 pt grid, with one
/// 2 pt step for optical adjustments.
public nonisolated enum Spacing {
    /// Optical nudges only, such as icon-side padding = text-side padding - 2.
    public static let hairline: CGFloat = 2
    public static let tight: CGFloat = 4
    public static let small: CGFloat = 8
    public static let medium: CGFloat = 12
    public static let large: CGFloat = 16
    public static let extraLarge: CGFloat = 24
    public static let section: CGFloat = 32

    /// Smallest side of any pointer target, whatever the size of its icon.
    public static let minimumHitArea: CGFloat = 40
}
