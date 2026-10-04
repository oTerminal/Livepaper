import SwiftUI

/// Between a normalised focal point (0 to 1 on each axis, top left to bottom
/// right) and the editor's coordinates. The editor shows the whole picture.
public nonisolated enum FocalPointMath {
    /// One arrow-key press.
    public static let nudge: CGFloat = 0.01

    /// Where the whole picture sits in an editor of `bounds`.
    public static func pictureRect(source: CGSize, in bounds: CGSize) -> CGRect {
        guard source.width > 0, source.height > 0 else { return CGRect(origin: .zero, size: bounds) }
        let scale = min(bounds.width / source.width, bounds.height / source.height)
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    public static func position(of focalPoint: UnitPoint, in pictureRect: CGRect) -> CGPoint {
        CGPoint(
            x: pictureRect.minX + focalPoint.x * pictureRect.width,
            y: pictureRect.minY + focalPoint.y * pictureRect.height
        )
    }

    /// The focal point under `location`, kept on the picture.
    public static func focalPoint(at location: CGPoint, in pictureRect: CGRect) -> UnitPoint {
        guard pictureRect.width > 0, pictureRect.height > 0 else { return .center }
        return UnitPoint(
            x: unit((location.x - pictureRect.minX) / pictureRect.width),
            y: unit((location.y - pictureRect.minY) / pictureRect.height)
        )
    }

    /// `focalPoint` moved by whole arrow-key steps.
    public static func nudged(_ focalPoint: UnitPoint, dx: Int, dy: Int) -> UnitPoint {
        UnitPoint(
            x: unit(focalPoint.x + CGFloat(dx) * nudge),
            y: unit(focalPoint.y + CGFloat(dy) * nudge)
        )
    }

    private static func unit(_ value: CGFloat) -> CGFloat {
        min(max(value, 0), 1)
    }
}
