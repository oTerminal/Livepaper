import Foundation
import LivepaperCore

/// The fakes run's commands for onboarding and the hotkeys, from the fakes
/// remote, so that the cards can be recorded where nothing
/// can drag a file or click in System Settings (`-onboarding YES` starts the run
/// on them), and a hotkey where the fakes register none. Each does what the
/// card's controls, or the world outside, would do.
///
///     onboarding open | onboarding primary | onboarding secondary
///     onboarding sample 2 | onboarding drop /path/to/file.mov
///     onboarding login answers needs approval (or on, not found, off)
///     onboarding store unreadable (or readable) | onboarding choose livepaper
///     install primary | install secondary | install move fails
///     hotkey pause (or next, mute, library)
///
/// The install card (`-install drag` or `move`) is pressed by `install`;
/// on the fakes, Move and the Applications folder are logged, and `install
/// move fails` makes the next Move fail.
struct FakesSystemCommands {
    let onboarding: Onboarding
    let installation: Installation
    let fakes: Fakes
    let windows: AppWindows

    /// Answers whether it was one of these.
    func perform(_ verb: String, _ rest: String) -> Bool {
        switch verb {
        case "onboarding":
            let words = rest.split(separator: " ", maxSplits: 1).map(String.init)
            guard let what = words.first else { return false }
            let detail = words.count > 1 ? words[1] : ""
            return card(what, detail) ?? world(what, detail) ?? false
        case "install":
            return install(rest)
        case "hotkey":
            let actions: [String: HotkeyAction] = [
                "pause": .pauseOrResumeAll, "next": .nextWallpaper, "mute": .mute, "library": .openLibrary,
            ]
            guard let action = actions[rest] else { return false }
            fakes.pressHotkey.yield(action)
            return true
        default:
            return false
        }
    }

    /// The card's own controls. Nil when the command is not one of these.
    private func card(_ what: String, _ detail: String) -> Bool? {
        let page = OnboardingPage(onboarding)
        switch what {
        case "open":
            windows.openOnboarding()
        case "primary":
            page.primary.run()
        case "secondary":
            guard let secondary = page.secondary else { return false }
            secondary.run()
        case "sample":
            guard let index = Int(detail), onboarding.samples.indices.contains(index - 1) else { return false }
            onboarding.pickSample(onboarding.samples[index - 1])
        case "drop":
            // As a drop on the card does it: a synthetic drag starts no drag session.
            onboarding.importWallpaper(from: [URL(filePath: detail)])
        default:
            return nil
        }
        return true
    }

    /// The install card's buttons, and a Move that fails.
    private func install(_ what: String) -> Bool {
        let page = InstallPage(installation)
        switch what {
        case "primary" where installation.isAsking: page.primary.run()
        case "secondary" where installation.isAsking: page.secondary.run()
        case "move fails": fakes.movesFail = true
        default: return false
        }
        return true
    }

    /// What macOS, WallpaperAgent's store and the user in System Settings would do.
    private func world(_ what: String, _ detail: String) -> Bool? {
        switch (what, detail) {
        case ("login", let answer) where answer.hasPrefix("answers "):
            let statuses: [String: LoginItemStatus] = ["on": .on, "needs approval": .needsApproval, "not found": .notFound, "off": .off]
            guard let status = statuses[String(answer.dropFirst("answers ".count))] else { return false }
            fakes.systemServices.answerToTurningOn = status
        case ("store", "unreadable"):
            fakes.selectionWorld.store.isReadable = false
        case ("store", "readable"):
            fakes.selectionWorld.store.isReadable = true
        case ("choose", "livepaper"):
            fakes.selectionWorld.chooseLivepaperInPane()
        default:
            return nil
        }
        return true
    }
}
