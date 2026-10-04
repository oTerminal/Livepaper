import AppKit
import DesignSystem
import SwiftUI

/// What the command line asks of this run: the fakes, and the Gallery's switches,
/// so that a recording of the app runs at 0.1x as the Gallery's does.
///
///     Livepaper -fakes YES -fakeLibrary seeded -slowMotion YES -reduceMotion YES -appearance Dark
///
/// Read from the launch arguments only, never from saved defaults, so a switch
/// lasts one run. A switch that is not given overrides nothing: the design system
/// then follows System Settings.
struct LaunchOptions: Equatable {
    enum Appearance: String {
        case light = "Light"
        case dark = "Dark"
    }

    /// The fakes run: fake render host, displays, sensors, library and importer.
    /// Nothing touches the real wallpaper.
    var isFakes = false
    /// What the fakes run's library starts with: `-fakeLibrary seeded` for screenshots.
    var fakeLibrary = FakeLibrary.empty
    /// The name the fakes run's remote answers to (`FakesRemote`), when two runs are up at once.
    var fakesRemote: String?
    /// The first launch the fakes run plays, so that onboarding can be recorded:
    /// `-onboarding YES`, `afterLeaving` or `updated`. The wired run ignores
    /// it: its onboarding follows the preferences alone.
    var onboarding: FakeOnboarding?
    /// Where the fakes run says Livepaper runs, so that the first launch's
    /// questions can be recorded: `-install drag` or `move`. The wired run
    /// ignores it: it reads where it runs.
    var install: FakeInstall?
    var slowMotion: Bool?
    var reduceMotion: Bool?
    var reduceTransparency: Bool?
    var increaseContrast: Bool?
    var appearance: Appearance?

    /// This process's arguments.
    static let current = LaunchOptions(arguments: UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain))

    /// `arguments` is the argument domain: each `-name value` pair, the value as
    /// the command line gave it.
    init(arguments: [String: Any]) {
        isFakes = Self.flag(arguments["fakes"]) ?? false
        fakeLibrary = (arguments["fakeLibrary"] as? String).flatMap(FakeLibrary.init) ?? .empty
        fakesRemote = arguments["fakesRemote"] as? String
        onboarding = (arguments["onboarding"] as? String).flatMap(FakeOnboarding.init(argument:))
        install = (arguments["install"] as? String).flatMap { FakeInstall(rawValue: $0.lowercased()) }
        slowMotion = Self.flag(arguments["slowMotion"])
        reduceMotion = Self.flag(arguments["reduceMotion"])
        reduceTransparency = Self.flag(arguments["reduceTransparency"])
        increaseContrast = Self.flag(arguments["increaseContrast"])
        appearance = (arguments["appearance"] as? String).flatMap(Appearance.init)
    }

    /// The design system's overrides: a switch given on or off overrides the
    /// system either way; one not given leaves it alone.
    var overrides: AccessibilityOverrides {
        AccessibilityOverrides(
            reduceMotion: reduceMotion,
            reduceTransparency: reduceTransparency,
            increaseContrast: increaseContrast,
            motionSpeed: slowMotion.map { $0 ? 0.1 : 1 }
        )
    }

    var colorScheme: ColorScheme? {
        switch appearance {
        case .light: .light
        case .dark: .dark
        case nil: nil
        }
    }

    /// The same, for AppKit: the menus and the popover's panel.
    var nsAppearance: NSAppearance? {
        switch appearance {
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        case nil: nil
        }
    }

    /// `YES`, `NO`, `true`, `false`, `1` or `0`, as `UserDefaults.bool(forKey:)` reads them.
    private static func flag(_ value: Any?) -> Bool? {
        switch value {
        case let number as NSNumber:
            number.boolValue
        case let string as String:
            switch string.lowercased() {
            case "yes", "true", "1": true
            case "no", "false", "0": false
            default: nil
            }
        default:
            nil
        }
    }
}

extension View {
    /// The root of every scene: the launch options' accessibility overrides and appearance.
    func launchOptions(_ options: LaunchOptions) -> some View {
        environment(\.accessibilityOverrides, options.overrides)
            .preferredColorScheme(options.colorScheme)
    }
}
