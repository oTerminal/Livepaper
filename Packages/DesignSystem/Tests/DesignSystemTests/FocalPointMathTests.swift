import SwiftUI
import Testing
import DesignSystem

struct FocalPointMathTests {
    private let picture = CGRect(x: 10, y: 20, width: 200, height: 100)

    @Test func `a wide picture is letterboxed in a square editor`() {
        let rect = FocalPointMath.pictureRect(source: CGSize(width: 1600, height: 900), in: CGSize(width: 400, height: 400))

        #expect(rect == CGRect(x: 0, y: 87.5, width: 400, height: 225))
    }

    @Test func `a picture with no size fills the editor`() {
        let rect = FocalPointMath.pictureRect(source: .zero, in: CGSize(width: 400, height: 300))

        #expect(rect == CGRect(x: 0, y: 0, width: 400, height: 300))
    }

    @Test(arguments: [
        (focal: UnitPoint(x: 0.5, y: 0.5), position: CGPoint(x: 110, y: 70)),
        (focal: UnitPoint(x: 0, y: 0), position: CGPoint(x: 10, y: 20)),
        (focal: UnitPoint(x: 1, y: 1), position: CGPoint(x: 210, y: 120)),
        (focal: UnitPoint(x: 0.25, y: 0.8), position: CGPoint(x: 60, y: 100)),
    ])
    func `a focal point maps to its place on the picture`(focal: UnitPoint, position: CGPoint) {
        #expect(FocalPointMath.position(of: focal, in: picture) == position)
    }

    @Test(arguments: [
        (location: CGPoint(x: 110, y: 70), focal: UnitPoint(x: 0.5, y: 0.5)),
        (location: CGPoint(x: 60, y: 100), focal: UnitPoint(x: 0.25, y: 0.8)),
    ])
    func `a location on the picture maps to a normalised focal point`(location: CGPoint, focal: UnitPoint) {
        #expect(FocalPointMath.focalPoint(at: location, in: picture) == focal)
    }

    @Test(arguments: [
        (location: CGPoint(x: -400, y: 70), focal: UnitPoint(x: 0, y: 0.5)),
        (location: CGPoint(x: 900, y: 900), focal: UnitPoint(x: 1, y: 1)),
        (location: CGPoint(x: 110, y: 0), focal: UnitPoint(x: 0.5, y: 0)),
    ])
    func `dragging off the picture keeps the focal point on its edge`(location: CGPoint, focal: UnitPoint) {
        #expect(FocalPointMath.focalPoint(at: location, in: picture) == focal)
    }

    @Test func `a picture with no area keeps the focal point in the middle`() {
        #expect(FocalPointMath.focalPoint(at: CGPoint(x: 5, y: 5), in: .zero) == UnitPoint(x: 0.5, y: 0.5))
    }

    @Test func `arrow keys nudge by a hundredth and stop at the edge`() {
        #expect(FocalPointMath.nudged(UnitPoint(x: 0.5, y: 0.5), dx: 1, dy: 0) == UnitPoint(x: 0.51, y: 0.5))
        #expect(FocalPointMath.nudged(UnitPoint(x: 1, y: 0), dx: 1, dy: -1) == UnitPoint(x: 1, y: 0))
    }
}
