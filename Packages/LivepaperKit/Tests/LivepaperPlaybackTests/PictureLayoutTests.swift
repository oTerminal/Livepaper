import CoreGraphics
import LivepaperCore
import Testing
@testable import LivepaperPlayback

struct PictureLayoutTests {
    struct Layout: Sendable {
        var presentation: Presentation
        var source: Size?
        var surface: SurfaceGeometry
    }

    // A 1000 x 1000 pixel surface at 2x is 500 x 500 points, and its layers' y grows upwards.
    private static let square = SurfaceGeometry(size: Size(width: 500, height: 500), scale: 2)

    static let rows: [Row<Layout, CGRect>] = [
        Row(
            "a portrait picture held by its top edge stays at the top of the surface",
            Layout(
                presentation: Presentation(fit: .fill, focalPoint: Point(x: 0.5, y: 0)),
                source: Size(width: 1000, height: 2000),
                surface: square
            ),
            CGRect(x: 0, y: -500, width: 500, height: 1000)
        ),
        Row(
            "a portrait picture held by its bottom edge stays at the bottom",
            Layout(
                presentation: Presentation(fit: .fill, focalPoint: Point(x: 0.5, y: 1)),
                source: Size(width: 1000, height: 2000),
                surface: square
            ),
            CGRect(x: 0, y: 0, width: 500, height: 1000)
        ),
        Row(
            "Fit leaves the same bar above and below",
            Layout(presentation: Presentation(fit: .fit), source: Size(width: 2000, height: 1000), surface: square),
            CGRect(x: 0, y: 125, width: 500, height: 250)
        ),
        Row(
            "Stretch covers the surface whatever the picture's shape",
            Layout(presentation: Presentation(fit: .stretch), source: Size(width: 2000, height: 1000), surface: square),
            CGRect(x: 0, y: 0, width: 500, height: 500)
        ),
        Row(
            "a picture of unknown size covers the surface",
            Layout(presentation: Presentation(fit: .fit), source: nil, surface: square),
            CGRect(x: 0, y: 0, width: 500, height: 500)
        ),
    ]

    @Test(arguments: rows)
    func `lays a picture out in the layer tree's points`(row: Row<Layout, CGRect>) {
        let frame = layerFrame(presentation: row.input.presentation, source: row.input.source, surface: row.input.surface)

        #expect(frame == row.expected)
    }

    @Test func `flips a rectangle at the top of the surface to the top in upward coordinates`() {
        let top = Rect(origin: Point(x: 10, y: 0), size: Size(width: 100, height: 40))

        #expect(flipped(top, within: 300) == CGRect(x: 10, y: 260, width: 100, height: 40))
    }
}
