import CoreGraphics
import Testing
import DesignSystem

struct RubberbandTests {
    @Test func `no overshoot gives no offset`() {
        #expect(rubberband(offset: 0, limit: 100) == 0)
    }

    @Test func `resistance grows the further past the edge the drag goes`() {
        let offsets = stride(from: CGFloat(0), through: 2000, by: 50).map { rubberband(offset: $0, limit: 100) }

        let steps = zip(offsets, offsets.dropFirst()).map { $1 - $0 }
        #expect(steps.allSatisfy { $0 > 0 })
        #expect(zip(steps, steps.dropFirst()).allSatisfy { $1 < $0 })
    }

    @Test(arguments: [CGFloat(1), 100, 10_000, 1_000_000])
    func `the offset never reaches the limit`(offset: CGFloat) {
        #expect(rubberband(offset: offset, limit: 100) < 100)
    }

    @Test func `dragging the other way mirrors the offset`() {
        #expect(rubberband(offset: -80, limit: 100) == -rubberband(offset: 80, limit: 100))
    }

    /// Worked example of Apple's formula with the 0.55 constant:
    /// 100 * 100 * 0.55 / (100 + 0.55 * 100) = 35.48...
    @Test func `an overshoot equal to the limit moves about a third of it`() {
        #expect(abs(rubberband(offset: 100, limit: 100) - 35.483_870_967) < 1e-6)
    }

    @Test func `a zero limit gives no offset`() {
        #expect(rubberband(offset: 50, limit: 0) == 0)
    }

    @Test(arguments: [CGFloat(-900), -40, 0, 12.5, 300, 5000])
    func `the drag that produced an offset can be recovered`(drag: CGFloat) {
        let offset = rubberband(offset: drag, limit: 60)

        #expect(abs(unrubberband(offset: offset, limit: 60) - drag) < 1e-6)
    }

    @Test func `an offset at or past the limit has no finite drag behind it`() {
        #expect(unrubberband(offset: 60, limit: 60) == .greatestFiniteMagnitude)
        #expect(unrubberband(offset: -75, limit: 60) == -.greatestFiniteMagnitude)
    }
}
