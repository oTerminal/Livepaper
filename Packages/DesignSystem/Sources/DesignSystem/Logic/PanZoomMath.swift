import SwiftUI

/// Where a zoomed and panned picture sits behind the editor's frame. Pan is a
/// fraction of the frame's size, so one value means the same on any display, and
/// every result is clamped so the picture always covers the frame.
public nonisolated enum PanZoomMath {
    public static let zoomRange: ClosedRange<CGFloat> = 1...4

    public static func clampedZoom(_ zoom: CGFloat) -> CGFloat {
        guard zoom.isFinite else { return zoomRange.lowerBound }
        return min(max(zoom, zoomRange.lowerBound), zoomRange.upperBound)
    }

    /// The picture's rectangle in the frame's coordinates.
    public static func pictureRect(
        source: CGSize,
        frame: CGSize,
        zoom: CGFloat,
        pan: CGSize,
        focalPoint: UnitPoint = .center
    ) -> CGRect {
        guard source.width > 0, source.height > 0 else { return CGRect(origin: .zero, size: frame) }
        let scale = max(frame.width / source.width, frame.height / source.height) * clampedZoom(zoom)
        let size = CGSize(width: source.width * scale, height: source.height * scale)
        return CGRect(
            x: origin(length: size.width, available: frame.width, focal: focalPoint.x, pan: pan.width),
            y: origin(length: size.height, available: frame.height, focal: focalPoint.y, pan: pan.height),
            width: size.width,
            height: size.height
        )
    }

    /// `pan` pulled back to what the frame allows, so a stored value never runs
    /// on past the picture's edge.
    public static func clampedPan(
        _ pan: CGSize,
        source: CGSize,
        frame: CGSize,
        zoom: CGFloat,
        focalPoint: UnitPoint = .center
    ) -> CGSize {
        guard frame.width > 0, frame.height > 0 else { return .zero }
        let placed = pictureRect(source: source, frame: frame, zoom: zoom, pan: pan, focalPoint: focalPoint)
        let resting = pictureRect(source: source, frame: frame, zoom: zoom, pan: .zero, focalPoint: focalPoint)
        return CGSize(
            width: (placed.minX - resting.minX) / frame.width,
            height: (placed.minY - resting.minY) / frame.height
        )
    }

    /// `pan` after a drag of `translation` points.
    public static func pan(_ pan: CGSize, movedBy translation: CGSize, frame: CGSize) -> CGSize {
        guard frame.width > 0, frame.height > 0 else { return pan }
        return CGSize(
            width: pan.width + translation.width / frame.width,
            height: pan.height + translation.height / frame.height
        )
    }

    /// One axis. The focal point is brought as near the middle as it can be, pan
    /// moves the picture from there, and the result never leaves a gap.
    private static func origin(length: CGFloat, available: CGFloat, focal: CGFloat, pan: CGFloat) -> CGFloat {
        let focal = focal.isFinite ? min(max(focal, 0), 1) : 0.5
        let pan = pan.isFinite ? pan : 0
        let wanted = available / 2 - focal * length + pan * available
        return min(max(wanted, available - length), 0)
    }
}
