import SwiftUI
import Testing
import DesignSystem

/// A 2:1 picture in a square frame: at zoom 1 it is 200 x 100 in a 100 x 100
/// frame, with 50 pt to spare on each side and none above or below.
struct PanZoomMathTests {
    private let source = CGSize(width: 2000, height: 1000)
    private let frame = CGSize(width: 100, height: 100)

    private func rect(zoom: CGFloat = 1, pan: CGSize = .zero, focalPoint: UnitPoint = .center) -> CGRect {
        PanZoomMath.pictureRect(source: source, frame: frame, zoom: zoom, pan: pan, focalPoint: focalPoint)
    }

    @Test func `at zoom 1 the picture fills the frame, centred`() {
        #expect(rect() == CGRect(x: -50, y: 0, width: 200, height: 100))
    }

    @Test func `zoom enlarges the picture about the middle`() {
        #expect(rect(zoom: 2) == CGRect(x: -150, y: -50, width: 400, height: 200))
    }

    @Test func `pan moves the picture by a fraction of the frame`() {
        #expect(rect(pan: CGSize(width: 0.25, height: 0)).origin == CGPoint(x: -25, y: 0))
    }

    @Test(arguments: [
        (pan: CGSize(width: 5, height: 0), origin: CGPoint(x: 0, y: 0)),
        (pan: CGSize(width: -5, height: 0), origin: CGPoint(x: -100, y: 0)),
        (pan: CGSize(width: 0, height: 5), origin: CGPoint(x: -50, y: 0)),
    ])
    func `pan stops where the picture's edge meets the frame's`(pan: CGSize, origin: CGPoint) {
        #expect(rect(pan: pan).origin == origin)
    }

    @Test(arguments: [CGFloat(1), 1.5, 4], [CGSize(width: -9, height: 9), CGSize(width: 0.3, height: -0.2), CGSize(width: 9, height: -9)])
    func `the picture always covers the frame`(zoom: CGFloat, pan: CGSize) {
        #expect(rect(zoom: zoom, pan: pan).contains(CGRect(origin: .zero, size: frame)))
    }

    @Test func `a stored pan is pulled back to what the frame allows`() {
        let pan = PanZoomMath.clampedPan(CGSize(width: 5, height: 3), source: source, frame: frame, zoom: 1)

        #expect(pan == CGSize(width: 0.5, height: 0))
    }

    @Test func `zooming out pulls the pan back in`() {
        let pan = PanZoomMath.clampedPan(CGSize(width: 1.5, height: 0.5), source: source, frame: frame, zoom: 1)

        #expect(pan == CGSize(width: 0.5, height: 0))
    }

    @Test func `a drag adds its translation as a fraction of the frame`() {
        let pan = PanZoomMath.pan(CGSize(width: 0.1, height: 0), movedBy: CGSize(width: 50, height: -25), frame: frame)

        #expect(pan == CGSize(width: 0.6, height: -0.25))
    }

    @Test(arguments: [
        (zoom: CGFloat(0.3), clamped: CGFloat(1)),
        (zoom: 2.5, clamped: 2.5),
        (zoom: 9, clamped: 4),
        (zoom: .nan, clamped: 1),
    ])
    func `zoom stays between 1 and 4`(zoom: CGFloat, clamped: CGFloat) {
        #expect(PanZoomMath.clampedZoom(zoom) == clamped)
    }

    @Test func `the focal point is brought towards the middle of the frame`() {
        #expect(rect(focalPoint: UnitPoint(x: 0, y: 0.5)).origin == CGPoint(x: 0, y: 0))
        #expect(rect(focalPoint: UnitPoint(x: 1, y: 0.5)).origin == CGPoint(x: -100, y: 0))
    }

    @Test func `a picture with no size fills the frame`() {
        let rect = PanZoomMath.pictureRect(source: .zero, frame: frame, zoom: 2, pan: .zero)

        #expect(rect == CGRect(origin: .zero, size: frame))
    }
}
