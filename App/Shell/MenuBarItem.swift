import AppKit
import DesignSystem
import SwiftUI

/// The menu-bar item: a click toggles the glass popover, a secondary click (or a
/// Control-click) shows a short menu of what the popover does not hold.
final class MenuBarItem: NSObject, NSMenuDelegate {
    /// The secondary-click menu's items, answered by whoever runs the app.
    struct Menu {
        /// "Check for Updates…": Sparkle's check, dimmed while it cannot run.
        var checkForUpdates: () -> Void
        var canCheckForUpdates: () -> Bool
        /// "Log Playback Metrics", a checkmark: a soak or a checklist switches it on.
        var isPlaybackMetricsOn: () -> Bool
        var setPlaybackMetrics: (Bool) -> Void
        /// The fakes run's "Fakes" submenu, built when the menu opens; nil leaves it out.
        var fakes: (() -> NSMenu)?
    }

    private let statusItem: NSStatusItem
    private let popover: MenuBarPopover
    private let menu: Menu
    private let appearance: NSAppearance?

    /// `content` is the popover's: it sits on the glass, so nothing in it is glass.
    /// `contentPadding` is `GlassPopover`'s: `Spacing.tight` for cards of `Radius.card`.
    init(options: LaunchOptions, menu: Menu, contentPadding: CGFloat = Spacing.medium, content: some View) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { preconditionFailure("A status item made by the status bar has a button") }
        button.image = NSImage(systemSymbolName: "play.rectangle.on.rectangle", accessibilityDescription: "Livepaper")
        button.setAccessibilityLabel("Livepaper")
        popover = MenuBarPopover(anchor: button, options: options, contentPadding: contentPadding, content: content)
        self.menu = menu
        appearance = options.nsAppearance
        super.init()
        button.target = self
        button.action = #selector(clicked)
        button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        // VoiceOver presses the item for the popover; the menu is an action of its own.
        button.setAccessibilityCustomActions([
            NSAccessibilityCustomAction(name: "Show Menu") { [weak self] in
                self?.showMenu()
                return true
            },
        ])
    }

    // Each with motion from a click, and without from a key press, VoiceOver or a hotkey.

    func togglePopover() {
        popover.toggle(animated: Self.isPointerEvent(NSApp.currentEvent))
    }

    func openPopover() {
        popover.open(animated: Self.isPointerEvent(NSApp.currentEvent))
    }

    func closePopover() {
        popover.close(animated: Self.isPointerEvent(NSApp.currentEvent))
    }

    /// For the fakes run's remote, which stands in for a click on an item that cannot be clicked.
    func openPopover(animated: Bool) {
        popover.open(animated: animated)
    }

    func closePopover(animated: Bool) {
        popover.close(animated: animated)
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        let isControlClick = event?.type == .leftMouseDown && event?.modifierFlags.contains(.control) == true
        if event?.type == .rightMouseDown || isControlClick {
            showMenu()
        } else {
            togglePopover()
        }
    }

    // MARK: The menu

    private func showMenu() {
        closePopover()
        statusItem.menu = makeMenu()
        // With a menu set, the button pops it up as a menu-bar item does, and
        // tracks it until it closes.
        statusItem.button?.performClick(nil)
    }

    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }

    private func makeMenu() -> NSMenu {
        let items = NSMenu(title: "Livepaper")
        items.delegate = self
        items.appearance = appearance

        // The standard About panel, with the notices from Credits.rtf.
        items.addItem(NSMenuItem("About Livepaper") {
            NSApp.activate()
            NSApp.orderFrontStandardAboutPanel(nil)
        })
        let updates = NSMenuItem("Check for Updates…") { [menu] in menu.checkForUpdates() }
        if !menu.canCheckForUpdates() {
            updates.action = nil
        }
        items.addItem(updates)
        items.addItem(.separator())

        let metrics = NSMenuItem("Log Playback Metrics") { [menu] in
            menu.setPlaybackMetrics(!menu.isPlaybackMetricsOn())
        }
        metrics.state = menu.isPlaybackMetricsOn() ? .on : .off
        items.addItem(metrics)

        if let fakes = menu.fakes {
            let item = NSMenuItem(title: "Fakes", action: nil, keyEquivalent: "")
            item.submenu = fakes()
            items.addItem(item)
        }

        items.addItem(.separator())
        items.addItem(NSMenuItem("Quit Livepaper", keyEquivalent: "q") {
            NSApp.terminate(nil)
        })
        return items
    }

    private static func isPointerEvent(_ event: NSEvent?) -> Bool {
        guard let type = event?.type else { return false }
        return [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp].contains(type)
    }
}

/// What a menu item built in code runs, such as the Fakes submenu's.
final class MenuAction: NSObject {
    private let handler: () -> Void

    init(_ handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run() {
        handler()
    }
}

extension NSMenuItem {
    /// An item that runs `handler` when chosen. The item keeps the handler.
    convenience init(_ title: String, keyEquivalent: String = "", handler: @escaping () -> Void) {
        let action = MenuAction(handler)
        self.init(title: title, action: #selector(MenuAction.run), keyEquivalent: keyEquivalent)
        target = action
        representedObject = action
    }
}
