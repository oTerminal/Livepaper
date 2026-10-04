import Foundation
import Testing
import DesignSystem

struct MotionTests {
    @Test(arguments: [
        Motion.Duration.hover,
        Motion.Duration.press,
        Motion.Duration.tooltip,
        Motion.Duration.popover,
        Motion.Duration.menu,
        Motion.Duration.panel,
    ])
    func `UI motion stays under 300 ms`(duration: TimeInterval) {
        #expect(duration < 0.3)
    }

    @Test func `sheets stay within 500 ms`() {
        #expect(Motion.Duration.sheet <= 0.5)
    }

    @Test func `elements enter from 0.96, never from nothing`() {
        #expect(Motion.enterScale == 0.96)
    }

    @Test func `a thrown element keeps the speed it was released at`() {
        #expect(Motion.Spring.momentum(initialVelocity: 3) == .interpolatingSpring(duration: 0.4, bounce: 0.2, initialVelocity: 3))
    }

    @Test func `exits are quicker than enters`() {
        let enter = Motion.Duration.popover

        #expect(Motion.Duration.exit(for: enter) < enter)
    }
}

struct ReducedMotionTests {
    @Test func `the Reduce Motion crossfade lasts 200 ms`() {
        #expect(Motion.Duration.reducedCrossfade == 0.2)
    }

    @Test func `with Reduce Motion the crossfade replaces a bouncy spring`() {
        #expect(Motion.resolve(Motion.Spring.momentum, reduceMotion: true) == Motion.reducedCrossfade)
    }

    @Test func `without Reduce Motion the animation is unchanged`() {
        #expect(Motion.resolve(Motion.Spring.momentum, reduceMotion: false) == Motion.Spring.momentum)
    }
}
