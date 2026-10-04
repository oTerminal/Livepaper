import Foundation
import Testing
import LivepaperCore

struct PresentationGeometryTests {
    static let landscape = Size(width: 2000, height: 1000)
    static let portrait = Size(width: 1000, height: 2000)
    static let small = Size(width: 1000, height: 500)

    struct Fitting: Sendable {
        var presentation: Presentation
        var source: Size
        var surface: Size
    }

    static func rect(_ x: Double, _ y: Double, _ width: Double, _ height: Double) -> Rect {
        Rect(origin: Point(x: x, y: y), size: Size(width: width, height: height))
    }

    // Expected rectangles are worked by hand. y grows downwards.
    static let rows: [Row<Fitting, Rect>] = [
        // Fit modes, same shape.
        Row(
            "fill, same shape: the picture is the surface",
            Fitting(presentation: Presentation(), source: small, surface: landscape),
            rect(0, 0, 2000, 1000)
        ),

        // Landscape on portrait and the reverse.
        Row(
            "fill, landscape on portrait: full height, sides cropped evenly",
            Fitting(presentation: Presentation(fit: .fill), source: landscape, surface: portrait),
            rect(-1500, 0, 4000, 2000)
        ),
        Row(
            "fill, portrait on landscape: full width, top and bottom cropped evenly",
            Fitting(presentation: Presentation(fit: .fill), source: portrait, surface: landscape),
            rect(0, -1500, 2000, 4000)
        ),
        Row(
            "fit, landscape on portrait: full width, centred between bars",
            Fitting(presentation: Presentation(fit: .fit), source: landscape, surface: portrait),
            rect(0, 750, 1000, 500)
        ),
        Row(
            "fit, portrait on landscape: full height, centred between bars",
            Fitting(presentation: Presentation(fit: .fit), source: portrait, surface: landscape),
            rect(750, 0, 500, 1000)
        ),
        Row(
            "stretch, landscape on portrait: the surface exactly, shape ignored",
            Fitting(presentation: Presentation(fit: .stretch), source: landscape, surface: portrait),
            rect(0, 0, 1000, 2000)
        ),
        Row(
            "stretch, portrait on landscape: the surface exactly, shape ignored",
            Fitting(presentation: Presentation(fit: .stretch), source: portrait, surface: landscape),
            rect(0, 0, 2000, 1000)
        ),

        // The focal point.
        Row(
            "fill: the focal point is brought to the middle of the surface",
            Fitting(presentation: Presentation(focalPoint: Point(x: 0.25, y: 0.5)), source: landscape, surface: portrait),
            rect(-500, 0, 4000, 2000)
        ),
        Row(
            "fill: a focal point on the left edge stops at the edge, no gap opens",
            Fitting(presentation: Presentation(focalPoint: Point(x: 0, y: 0.5)), source: landscape, surface: portrait),
            rect(0, 0, 4000, 2000)
        ),
        Row(
            "fill: a focal point on the right edge stops at the edge, no gap opens",
            Fitting(presentation: Presentation(focalPoint: Point(x: 1, y: 0.5)), source: landscape, surface: portrait),
            rect(-3000, 0, 4000, 2000)
        ),
        Row(
            "fill: a focal point outside the picture counts as the nearest edge",
            Fitting(presentation: Presentation(focalPoint: Point(x: 7, y: -3)), source: landscape, surface: portrait),
            rect(-3000, 0, 4000, 2000)
        ),

        // Pan and zoom.
        Row(
            "zoom 2 doubles the picture about the focal point",
            Fitting(presentation: Presentation(zoom: 2), source: small, surface: landscape),
            rect(-1000, -500, 4000, 2000)
        ),
        Row(
            "pan moves the picture by a fraction of the surface",
            Fitting(presentation: Presentation(zoom: 2, pan: Point(x: 0.25, y: 0)), source: small, surface: landscape),
            rect(-500, -500, 4000, 2000)
        ),
        Row(
            "pan too far right and down clamps at the picture's top left",
            Fitting(presentation: Presentation(zoom: 2, pan: Point(x: 5, y: 5)), source: small, surface: landscape),
            rect(0, 0, 4000, 2000)
        ),
        Row(
            "pan too far left and up clamps at the picture's bottom right",
            Fitting(presentation: Presentation(zoom: 2, pan: Point(x: -5, y: -5)), source: small, surface: landscape),
            rect(-2000, -1000, 4000, 2000)
        ),
        Row(
            "pan stops where the focal point would leave the surface",
            Fitting(
                presentation: Presentation(focalPoint: Point(x: 0.75, y: 0.5), pan: Point(x: 1, y: 0)), source: landscape, surface: portrait
            ),
            rect(-2000, 0, 4000, 2000)
        ),
        Row(
            "zoom below 1 clamps to 1",
            Fitting(presentation: Presentation(zoom: 0.5), source: small, surface: landscape),
            rect(0, 0, 2000, 1000)
        ),
        Row(
            "a zoom that is not a number counts as 1",
            Fitting(presentation: Presentation(zoom: .nan), source: small, surface: landscape),
            rect(0, 0, 2000, 1000)
        ),
        Row(
            "with nothing cropped there is nowhere to pan",
            Fitting(presentation: Presentation(pan: Point(x: 0.3, y: -0.3)), source: small, surface: landscape),
            rect(0, 0, 2000, 1000)
        ),
        Row(
            "stretch zooms too",
            Fitting(presentation: Presentation(fit: .stretch, zoom: 2), source: landscape, surface: portrait),
            rect(-500, -1000, 2000, 4000)
        ),
        Row(
            "fit, zoomed: the covered axis clamps, the other stays centred",
            Fitting(presentation: Presentation(fit: .fit, zoom: 2, pan: Point(x: 0, y: 0.4)), source: landscape, surface: portrait),
            rect(-500, 500, 2000, 1000)
        ),

        // Nothing to fit.
        Row(
            "a source with no size takes the surface",
            Fitting(presentation: Presentation(), source: Size(width: 0, height: 1000), surface: landscape),
            rect(0, 0, 2000, 1000)
        ),
    ]

    @Test(arguments: rows)
    func `fits the picture to the surface`(row: Row<Fitting, Rect>) {
        let picture = pictureRect(for: row.input.presentation, source: row.input.source, surface: row.input.surface)

        #expect(picture.isClose(to: row.expected), "\(picture)")
    }

    struct Shapes: Sendable, CustomTestStringConvertible {
        var source: Size
        var surface: Size

        var testDescription: String {
            "\(Int(source.width))x\(Int(source.height)) on \(Int(surface.width))x\(Int(surface.height))"
        }
    }

    static let sources = [landscape, portrait, small, Size(width: 3840, height: 2160), Size(width: 1080, height: 1350)]
    static let surfaces = [landscape, portrait, Size(width: 3024, height: 1964), Size(width: 1440, height: 2560)]
    static let shapes: [Shapes] = sources.flatMap { source in
        surfaces.map { Shapes(source: source, surface: $0) }
    }

    /// Every focal point on a 5 x 5 grid, at three zooms, with no pan and with a pan far past every edge.
    static let fillPresentations: [Presentation] = [0.0, 0.25, 0.5, 0.75, 1.0].flatMap { focalX in
        [0.0, 0.25, 0.5, 0.75, 1.0].flatMap { focalY in
            [1.0, 1.7, 4.0].flatMap { zoom in
                [Point(x: 0, y: 0), Point(x: 3, y: -3), Point(x: -3, y: 3)].map { pan in
                    Presentation(fit: .fill, focalPoint: Point(x: focalX, y: focalY), zoom: zoom, pan: pan)
                }
            }
        }
    }

    @Test(arguments: shapes, fillPresentations)
    func `when filling, the picture covers the surface and the focal point stays in view`(shapes: Shapes, presentation: Presentation) {
        let (source, surface) = (shapes.source, shapes.surface)
        let slack = 1e-9

        let picture = pictureRect(for: presentation, source: source, surface: surface)

        let focal = Point(
            x: picture.origin.x + presentation.focalPoint.x * picture.size.width,
            y: picture.origin.y + presentation.focalPoint.y * picture.size.height
        )
        #expect(picture.origin.x <= slack && picture.origin.y <= slack, "\(picture)")
        #expect(picture.maxX >= surface.width - slack && picture.maxY >= surface.height - slack, "\(picture)")
        #expect(abs(picture.size.width / picture.size.height - source.width / source.height) < slack, "\(picture)")
        #expect((-slack...surface.width + slack).contains(focal.x), "\(picture)")
        #expect((-slack...surface.height + slack).contains(focal.y), "\(picture)")
    }

    @Test func `a presentation is fill, centred and unzoomed unless the user says otherwise`() {
        let presentation = Presentation()

        #expect(presentation.fit == .fill)
        #expect(presentation.focalPoint == Point(x: 0.5, y: 0.5))
        #expect(presentation.zoom == 1)
        #expect(presentation.pan == Point(x: 0, y: 0))
    }
}

extension Rect {
    func isClose(to other: Rect, tolerance: Double = 1e-9) -> Bool {
        abs(origin.x - other.origin.x) <= tolerance && abs(origin.y - other.origin.y) <= tolerance
            && abs(size.width - other.size.width) <= tolerance && abs(size.height - other.size.height) <= tolerance
    }
}
