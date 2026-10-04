import AppKit
import LivepaperCore

// Settings: the pause rules, the login item, the hotkeys, and leaving Livepaper.
// The last three talk to `SystemServices`: `MacSystemServices` wired, the fake
// in the fakes run.

extension AppModel {
    // MARK: Pause rules

    /// Saved, applied, and handed to the sensing, which senses what the rules now need.
    func setPauseRules(_ rules: PauseRules) {
        var next = state
        next.pauseRules = rules
        commit(state: next)
        sensing?.rules = rules
    }

    /// One rule, such as `\.onBattery`.
    func setPauseRule(_ rule: WritableKeyPath<PauseRules, Bool>, _ isOn: Bool) {
        var rules = state.pauseRules
        rules[keyPath: rule] = isOn
        setPauseRules(rules)
    }

    // MARK: The login item

    /// The switch moves to what the system answers, in the same turn.
    func setOpenAtLogin(_ isOn: Bool) {
        _ = systemServices.setOpenAtLogin(isOn)
    }

    func openLoginItemsSettings() {
        systemServices.openLoginItemsSettings()
    }

    // MARK: Hotkeys

    /// Nil clears it. Hotkeys ship unassigned.
    func assignHotkey(_ combination: KeyCombination?, to action: HotkeyAction) {
        systemServices.assign(combination, to: action)
    }

    // MARK: Leaving

    /// "Stop using Livepaper as wallpaper", once confirmed: the previous wallpaper
    /// goes back and the login item goes, then the app quits, holding the
    /// stopped state as a quit does. The library is kept, and the next launch
    /// offers onboarding's last card alone.
    func leaveLivepaper() {
        guard hasStarted else { return }
        let services = systemServices
        Task {
            await services.leaveLivepaper()
            recordLeaving()
            // From the run loop, not this task: Terminate waits in a nested run loop
            // for the quit, whose task would otherwise queue behind this one.
            NSApp.perform(#selector(NSApplication.terminate(_:)), with: nil, afterDelay: 0)
        }
    }
}
