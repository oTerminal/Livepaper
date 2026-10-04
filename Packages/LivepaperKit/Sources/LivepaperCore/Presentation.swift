public enum FitMode: String, Codable, CaseIterable, Sendable {
    /// Cover the display, cropping what does not fit.
    case fill
    /// Show the whole wallpaper, with bars where the shapes differ.
    case fit
    /// Cover the display exactly, ignoring the wallpaper's shape.
    case stretch
}

/// How a wallpaper is fitted to a display.
public struct Presentation: Codable, Equatable, Sendable {
    public var fit: FitMode
    /// The part of the wallpaper that stays in view when it is cropped, in unit
    /// coordinates: (0, 0) is the top left of the picture and (1, 1) the bottom right.
    public var focalPoint: Point
    /// 1 or more. 1 is the fit mode's own size.
    public var zoom: Double
    /// How far the picture is moved, as a fraction of the surface's size, so
    /// that the same pan means the same thing on every display.
    public var pan: Point

    public init(
        fit: FitMode = .fill,
        focalPoint: Point = Point(x: 0.5, y: 0.5),
        zoom: Double = 1,
        pan: Point = Point(x: 0, y: 0)
    ) {
        self.fit = fit
        self.focalPoint = focalPoint
        self.zoom = zoom
        self.pan = pan
    }
}

/// Where the picture goes, in the surface's coordinates.
///
/// The fit mode gives the size, and zoom enlarges it. The focal point is then
/// brought as near to the middle of the surface as it can be, pan moves the
/// picture from there, and last each axis is clamped: an axis the picture
/// covers never shows a gap and keeps the focal point on the surface, and an
/// axis it does not cover (Fit's bars) is centred.
public func pictureRect(for presentation: Presentation, source: Size, surface: Size) -> Rect {
    guard source.width > 0, source.height > 0 else {
        return Rect(origin: Point(x: 0, y: 0), size: surface)
    }

    let widthScale = surface.width / source.width
    let heightScale = surface.height / source.height
    let zoom = presentation.zoom.isFinite ? max(presentation.zoom, 1) : 1
    let size: Size = switch presentation.fit {
    case .fill: source.scaled(by: max(widthScale, heightScale) * zoom)
    case .fit: source.scaled(by: min(widthScale, heightScale) * zoom)
    case .stretch: surface.scaled(by: zoom)
    }

    return Rect(
        origin: Point(
            x: placed(length: size.width, within: surface.width, focal: presentation.focalPoint.x, pan: presentation.pan.x),
            y: placed(length: size.height, within: surface.height, focal: presentation.focalPoint.y, pan: presentation.pan.y)
        ),
        size: size
    )
}

/// One axis: where a picture of `length` starts on a surface of `available`.
private func placed(length: Double, within available: Double, focal: Double, pan: Double) -> Double {
    guard length > available else { return (available - length) / 2 }
    let focal = focal.isFinite ? min(max(focal, 0), 1) : 0.5
    let pan = pan.isFinite ? pan : 0
    let wanted = available / 2 - focal * length + pan * available
    // Both limits at once: no gap at either edge, and the focal point on the surface.
    let lowest = max(available - length, -focal * length)
    let highest = min(0, available - focal * length)
    return min(max(wanted, lowest), highest)
}

extension Size {
    fileprivate func scaled(by factor: Double) -> Size {
        Size(width: width * factor, height: height * factor)
    }
}
