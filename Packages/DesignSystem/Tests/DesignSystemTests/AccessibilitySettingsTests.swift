import Testing
import DesignSystem

/// Overrides over System Settings: the rule `@Accessibility` and AppKit code share.
struct AccessibilitySettingsTests {
    nonisolated struct System: Sendable {
        var reduceMotion = false
        var reduceTransparency = false
        var increaseContrast = false

        static let allOn = System(reduceMotion: true, reduceTransparency: true, increaseContrast: true)
    }

    nonisolated struct Case: Sendable, CustomTestStringConvertible {
        let name: String
        let overrides: AccessibilityOverrides
        /// What System Settings has.
        let system: System
        let expected: AccessibilitySettings

        var testDescription: String { name }
    }

    nonisolated static let cases: [Case] = [
        Case(
            name: "no override follows the system, off",
            overrides: AccessibilityOverrides(),
            system: System(),
            expected: AccessibilitySettings()
        ),
        Case(
            name: "no override follows the system, on",
            overrides: AccessibilityOverrides(),
            system: .allOn,
            expected: AccessibilitySettings(reduceMotion: true, reduceTransparency: true, increaseContrast: true)
        ),
        Case(
            name: "an override on beats the system off",
            overrides: AccessibilityOverrides(reduceMotion: true, reduceTransparency: true, increaseContrast: true),
            system: System(),
            expected: AccessibilitySettings(reduceMotion: true, reduceTransparency: true, increaseContrast: true)
        ),
        Case(
            name: "an override off beats the system on",
            overrides: AccessibilityOverrides(reduceMotion: false, reduceTransparency: false, increaseContrast: false),
            system: .allOn,
            expected: AccessibilitySettings()
        ),
        Case(
            name: "each setting on its own: one overridden, the others followed",
            overrides: AccessibilityOverrides(increaseContrast: false),
            system: System(reduceMotion: true, increaseContrast: true),
            expected: AccessibilitySettings(reduceMotion: true)
        ),
        Case(
            name: "motion speed takes the override: the Gallery's 0.1x",
            overrides: AccessibilityOverrides(motionSpeed: 0.1),
            system: System(),
            expected: AccessibilitySettings(motionSpeed: 0.1)
        ),
    ]

    @Test(arguments: cases)
    func `an override given wins either way, one not given follows the system`(row: Case) {
        let settings = AccessibilitySettings(
            overrides: row.overrides,
            systemReduceMotion: row.system.reduceMotion,
            systemReduceTransparency: row.system.reduceTransparency,
            systemIncreaseContrast: row.system.increaseContrast
        )

        #expect(settings == row.expected)
    }

    @Test func `motion speed is 1 without an override, whatever the system`() {
        let settings = AccessibilitySettings(
            overrides: AccessibilityOverrides(), systemReduceMotion: true, systemReduceTransparency: true, systemIncreaseContrast: true
        )

        #expect(settings.motionSpeed == 1)
    }
}
