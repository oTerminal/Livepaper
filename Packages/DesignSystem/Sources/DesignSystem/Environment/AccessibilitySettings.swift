import AppKit
import SwiftUI

/// The accessibility settings a component adapts to. Components read these
/// through `@Accessibility`, never the system environment values directly, so
/// the Gallery can override them for one page without touching System Settings.
public nonisolated struct AccessibilitySettings: Equatable, Sendable {
    public var reduceMotion: Bool
    public var reduceTransparency: Bool
    public var increaseContrast: Bool
    /// 1 everywhere except the Gallery's slow-motion switch.
    public var motionSpeed: Double

    public init(
        reduceMotion: Bool = false,
        reduceTransparency: Bool = false,
        increaseContrast: Bool = false,
        motionSpeed: Double = 1
    ) {
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.increaseContrast = increaseContrast
        self.motionSpeed = motionSpeed
    }

    /// The animation to run for a pointer-driven change: the crossfade under
    /// Reduce Motion, `animation` otherwise.
    public func animation(_ animation: Animation) -> Animation {
        let resolved = Motion.resolve(animation, reduceMotion: reduceMotion)
        return motionSpeed == 1 ? resolved : resolved.speed(motionSpeed)
    }

    /// The animation for a change of opacity or colour only. Nothing moves, so
    /// Reduce Motion leaves it as it is: reduced motion keeps fades and drops movement.
    public func fade(_ animation: Animation) -> Animation {
        motionSpeed == 1 ? animation : animation.speed(motionSpeed)
    }

    /// How an SF Symbol swaps for another: the replace effect, or a plain fade
    /// under Reduce Motion.
    public var symbolReplace: ContentTransition {
        reduceMotion ? .opacity : .symbolEffect(.replace)
    }

    /// The entrance delay for the item at `index` of a staggered group.
    public func staggerDelay(forIndex index: Int) -> TimeInterval {
        Stagger.delay(forIndex: index, reduceMotion: reduceMotion) / motionSpeed
    }

    /// The entrance delay for a group of an onboarding card.
    public func staggerDelay(forOnboardingGroup group: Int) -> TimeInterval {
        Stagger.delay(forOnboardingGroup: group, reduceMotion: reduceMotion) / motionSpeed
    }

    public var contrast: ColorSchemeContrast {
        increaseContrast ? .increased : .standard
    }
}

extension AccessibilitySettings {
    /// The system's settings with `overrides` on top: an override given on or
    /// off wins either way, one not given follows the system. The one place that
    /// rule lives: `@Accessibility` and `system(overriding:)` both come here.
    public nonisolated init(
        overrides: AccessibilityOverrides,
        systemReduceMotion: Bool,
        systemReduceTransparency: Bool,
        systemIncreaseContrast: Bool
    ) {
        self.init(
            reduceMotion: overrides.reduceMotion ?? systemReduceMotion,
            reduceTransparency: overrides.reduceTransparency ?? systemReduceTransparency,
            increaseContrast: overrides.increaseContrast ?? systemIncreaseContrast,
            motionSpeed: overrides.motionSpeed ?? 1
        )
    }

    /// What `@Accessibility` gives a view under `overrides`, for AppKit code that
    /// starts a change the design system animates before any view has read it:
    /// System Settings as `NSWorkspace` has them, the overrides on top.
    public static func system(overriding overrides: AccessibilityOverrides) -> AccessibilitySettings {
        let workspace = NSWorkspace.shared
        return AccessibilitySettings(
            overrides: overrides,
            systemReduceMotion: workspace.accessibilityDisplayShouldReduceMotion,
            systemReduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            systemIncreaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast
        )
    }
}

/// Replaces individual system settings for a subtree. `nil` follows the system.
public nonisolated struct AccessibilityOverrides: Equatable, Sendable {
    public var reduceMotion: Bool?
    public var reduceTransparency: Bool?
    public var increaseContrast: Bool?
    public var motionSpeed: Double?

    public init(
        reduceMotion: Bool? = nil,
        reduceTransparency: Bool? = nil,
        increaseContrast: Bool? = nil,
        motionSpeed: Double? = nil
    ) {
        self.reduceMotion = reduceMotion
        self.reduceTransparency = reduceTransparency
        self.increaseContrast = increaseContrast
        self.motionSpeed = motionSpeed
    }
}

extension EnvironmentValues {
    @Entry public var accessibilityOverrides = AccessibilityOverrides()
}

/// The accessibility settings in effect for this view: the system's, with any
/// `accessibilityOverrides` applied on top.
@propertyWrapper
public struct Accessibility: DynamicProperty {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityOverrides) private var overrides

    public init() {}

    public var wrappedValue: AccessibilitySettings {
        AccessibilitySettings(
            overrides: overrides,
            systemReduceMotion: reduceMotion,
            systemReduceTransparency: reduceTransparency,
            systemIncreaseContrast: contrast == .increased
        )
    }
}
