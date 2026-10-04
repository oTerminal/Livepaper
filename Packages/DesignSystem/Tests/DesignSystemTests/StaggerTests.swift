import Foundation
import Testing
import DesignSystem

struct StaggerTests {
    @Test(arguments: [
        (index: 0, delay: 0.0),
        (index: 1, delay: 0.04),
        (index: 5, delay: 0.20),
        (index: 7, delay: 0.28),
    ])
    func `delay grows by 40 ms per item up to the cap`(index: Int, delay: TimeInterval) {
        #expect(abs(Stagger.delay(forIndex: index) - delay) < 1e-9)
    }

    @Test(arguments: [8, 9, 40, 10_000])
    func `items past the eighth arrive with the eighth`(index: Int) {
        #expect(abs(Stagger.delay(forIndex: index) - 0.28) < 1e-9)
    }

    @Test func `a negative index does not run ahead of the first item`() {
        #expect(Stagger.delay(forIndex: -3) == 0)
    }

    @Test(arguments: [(group: 0, delay: 0.0), (group: 1, delay: 0.10), (group: 3, delay: 0.30)])
    func `onboarding groups are 100 ms apart`(group: Int, delay: TimeInterval) {
        #expect(abs(Stagger.delay(forOnboardingGroup: group) - delay) < 1e-9)
    }

    @Test func `with Reduce Motion nothing staggers`() {
        #expect(Stagger.delay(forIndex: 5, reduceMotion: true) == 0)
        #expect(Stagger.delay(forOnboardingGroup: 2, reduceMotion: true) == 0)
    }
}
