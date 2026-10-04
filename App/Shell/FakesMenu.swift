import AppKit
import LivepaperCore

extension Fakes {
    /// The fakes run's "Fakes" submenu, in the menu-bar item's secondary-click
    /// menu: the fake host's status and the fake conditions, for the manual
    /// script and the screenshots, the popover's buttons, and the login item's
    /// four states for Settings'. Built each time the menu opens, so the
    /// checkmarks are current.
    func menu(model: AppModel, openPopover: @escaping () -> Void) -> NSMenu {
        let menu = NSMenu(title: "Fakes")
        // The menu bar can be too full to show the item.
        menu.addItem(NSMenuItem("Open Popover", handler: openPopover))
        // Every import row's state, a Wallpaper Engine item and a skipped scene; again, and they are duplicates.
        menu.addItem(NSMenuItem("Import Sample Files") { [weak self] in
            guard let self, let files = try? writeSampleFiles() else { return }
            model.importItems(at: files)
        })

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Wallpaper Service"))
        for (title, status) in Self.statuses {
            let item = NSMenuItem(title) { [host] in host.report(status) }
            item.state = model.hostStatus == status ? .on : .off
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Conditions"))
        func condition(_ title: String, isOn: Bool, toggle: @escaping () -> Void) {
            let item = NSMenuItem(title, handler: toggle)
            item.state = isOn ? .on : .off
            menu.addItem(item)
        }
        let display = Self.names[firstDisplay.identity] ?? "First Display"
        condition("Desktop Covered on \(display)", isOn: isDesktopCovered, toggle: toggleDesktopCovered)
        condition("\(display) Asleep", isOn: isDisplayAsleep, toggle: toggleDisplayAsleep)
        condition("Locked", isOn: isLocked, toggle: toggleLocked)
        condition("Low Power Mode", isOn: isLowPowerMode, toggle: toggleLowPowerMode)
        condition("On Battery", isOn: isOnBattery, toggle: toggleOnBattery)
        menu.addItem(sleepAndWake)

        // What the popover's buttons do, for a run whose popover nothing can click:
        // the fakes remote's `menu Pause All`.
        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Popover"))
        let first = firstDisplay.identity
        let second = Self.studio.identity
        let secondName = Self.names[second] ?? "Second Display"
        let cards = model.nowPlaying
        condition("Pause \(display)", isOn: cards.first { $0.display == first }?.isUserPaused == true) {
            model.togglePause(on: first)
        }
        let isOnPlaylist = cards.first { $0.display == second }?.playlist != nil
        condition("Playlist on \(secondName)", isOn: isOnPlaylist) {
            model.choosePlaylist(isOnPlaylist ? nil : model.playlists.first?.id, for: second)
        }
        condition("Pause All", isOn: model.isPausedAll) { model.togglePauseAll() }
        condition("Mute", isOn: model.isMuted) { model.toggleMute() }

        menu.addItem(.separator())
        menu.addItem(.sectionHeader(title: "Login Item"))
        for (title, status) in Self.loginItemStatuses {
            let item = NSMenuItem(title) { [systemServices] in systemServices.loginItem = status }
            item.state = systemServices.loginItem == status ? .on : .off
            menu.addItem(item)
        }
        return menu
    }

    /// The rotation driver moves each playlist on at a wake.
    private var sleepAndWake: NSMenuItem {
        NSMenuItem("Sleep and Wake") { [sleep] in
            sleep.send(.willSleep)
            sleep.send(.didWake)
        }
    }

    private static let statuses: [(String, RenderHostStatus)] = [
        ("Connecting", .connecting),
        ("Live", .live),
        ("Not Selected", .notSelected),
        ("Unavailable", .unavailable),
        ("Recovering at Flush", .recovering(.flush)),
        ("Recovering at Restart Agent", .recovering(.restartAgent)),
        ("Stopped", .stopped),
    ]

    private static let loginItemStatuses: [(String, LoginItemStatus)] = [
        ("Off", .off),
        ("On", .on),
        ("Needs Approval", .needsApproval),
        ("Not Found", .notFound),
    ]
}
