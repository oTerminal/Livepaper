import CoreGraphics
import Testing
import DesignSystem

struct RadiusTests {
    /// Worked examples from make-interfaces-feel-better (surfaces.md).
    @Test(arguments: [
        (inner: 12.0, padding: 8.0, outer: 20.0),
        (inner: 8.0, padding: 8.0, outer: 16.0),
        (inner: 0.0, padding: 4.0, outer: 4.0),
    ])
    func `outer radius is inner radius plus padding`(inner: CGFloat, padding: CGFloat, outer: CGFloat) {
        #expect(Radius.outer(inner: inner, padding: padding) == outer)
    }

    @Test func `the scale steps by whole concentric paddings`() {
        #expect(Radius.control == 8)
        #expect(Radius.tile == 12)
        #expect(Radius.card == 16)
        #expect(Radius.panel == 20)
    }
}
