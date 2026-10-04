import DesignSystem
import SwiftUI

/// The toolbar's switches. They override the environment for the page; they do
/// not change System Settings.
@Observable
final class GallerySettings {
    enum Appearance: String, CaseIterable, Identifiable {
        case system = "System"
        case light = "Light"
        case dark = "Dark"

        var id: Self { self }

        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .light: .light
            case .dark: .dark
            }
        }
    }

    var slowMotion = false
    var reduceMotion = false
    var reduceTransparency = false
    var increaseContrast = false
    var busyBackdrop = false
    var appearance = Appearance.system

    /// The switches start where System Settings has them, and can be preset from
    /// the command line, such as `-busyBackdrop YES -appearance Dark`.
    init(defaults: UserDefaults = .standard, workspace: NSWorkspace = .shared) {
        slowMotion = defaults.bool(forKey: "slowMotion")
        reduceMotion = defaults.bool(forKey: "reduceMotion") || workspace.accessibilityDisplayShouldReduceMotion
        reduceTransparency = defaults.bool(forKey: "reduceTransparency") || workspace.accessibilityDisplayShouldReduceTransparency
        increaseContrast = defaults.bool(forKey: "increaseContrast") || workspace.accessibilityDisplayShouldIncreaseContrast
        busyBackdrop = defaults.bool(forKey: "busyBackdrop")
        appearance = defaults.string(forKey: "appearance").flatMap(Appearance.init) ?? .system
    }

    /// Every switch overrides, on or off, so a setting that is on in System
    /// Settings can be turned off for the page too.
    var overrides: AccessibilityOverrides {
        AccessibilityOverrides(
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency,
            increaseContrast: increaseContrast,
            motionSpeed: slowMotion ? 0.1 : 1
        )
    }
}
