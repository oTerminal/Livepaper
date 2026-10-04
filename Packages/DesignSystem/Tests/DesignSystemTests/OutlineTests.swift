import SwiftUI
import Testing
import DesignSystem

struct OutlineTests {
    @Test func `the outline is one point wide`() {
        #expect(Outline.width == 1)
    }

    @Test func `light mode outlines are pure black at 10 percent`() {
        #expect(Outline.stroke(scheme: .light, contrast: .standard) == Outline.Stroke(white: 0, opacity: 0.10))
    }

    @Test func `dark mode outlines are pure white at 10 percent`() {
        #expect(Outline.stroke(scheme: .dark, contrast: .standard) == Outline.Stroke(white: 1, opacity: 0.10))
    }

    @Test(arguments: [ColorScheme.light, .dark])
    func `with Increase Contrast the outline is stronger but not tinted`(scheme: ColorScheme) {
        let standard = Outline.stroke(scheme: scheme, contrast: .standard)
        let increased = Outline.stroke(scheme: scheme, contrast: .increased)

        #expect(increased.white == standard.white)
        #expect(increased.opacity == 0.35)
    }
}
