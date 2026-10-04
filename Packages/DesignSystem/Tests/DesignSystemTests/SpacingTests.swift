import CoreGraphics
import Testing
import DesignSystem

struct SpacingTests {
    @Test func `the scale sits on a 4 pt grid with a 2 pt hairline step`() {
        #expect(Spacing.hairline == 2)
        #expect(Spacing.tight == 4)
        #expect(Spacing.small == 8)
        #expect(Spacing.medium == 12)
        #expect(Spacing.large == 16)
        #expect(Spacing.extraLarge == 24)
        #expect(Spacing.section == 32)
    }

    /// make-interfaces-feel-better: dense desktop controls keep a 40 x 40 hit area.
    @Test func `the minimum hit area is 40 pt`() {
        #expect(Spacing.minimumHitArea == 40)
    }
}
