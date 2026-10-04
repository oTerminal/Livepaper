import Foundation
import Testing
import DesignSystem

/// When a new primary button of an `OnboardingCard` takes the focus: never while
/// the step it replaces is still fading out.
struct OnboardingCardFocusTests {
    @Test func `a new title within a step takes the focus at once`() {
        #expect(OnboardingCardFocus.delay(stepChanged: false, crossfades: true, motionSpeed: 1) == 0)
    }

    @Test func `a step changed by Return, with nothing fading, takes it at once`() {
        #expect(OnboardingCardFocus.delay(stepChanged: true, crossfades: false, motionSpeed: 1) == 0)
    }

    @Test(arguments: [(speed: 1.0, delay: 0.20), (speed: 0.1, delay: 2.0)])
    func `a step that crossfades takes it when the crossfade is over`(speed: Double, delay: TimeInterval) {
        let wait = OnboardingCardFocus.delay(stepChanged: true, crossfades: true, motionSpeed: speed)
        #expect(abs(wait - delay) < 1e-9)
    }
}
