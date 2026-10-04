import AppKit

/// Lets a script drive the fakes run, and only the fakes run: the manual script
/// and the PR's media need the popover, the windows and the Fakes menu on cue,
/// and on a Mac whose menu-bar item sits under the notch nothing can click them.
///
///     open popover
///     menu "Recovering at Restart Agent"
///
/// A command is words: a verb, then what it acts on. Unknown commands are logged and ignored.
/// Two fakes runs at once keep apart by name: `-fakesRemote <name>` on the run,
/// `LIVEPAPER_FAKES=<name>` for the script.
final class FakesRemote: NSObject {
    /// The distributed notification a command arrives by; its object is the command.
    static let notification = Notification.Name(
        "app.livepaper.fakes.command" + (LaunchOptions.current.fakesRemote.map { ".\($0)" } ?? "")
    )

    private let perform: @MainActor (_ verb: String, _ rest: String) -> Void

    init(perform: @escaping @MainActor (_ verb: String, _ rest: String) -> Void) {
        self.perform = perform
        super.init()
        // At once, active or not: NSApplication holds distributed notifications back
        // while the app is inactive, and an agent app mostly is.
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(received(_:)), name: Self.notification, object: nil, suspensionBehavior: .deliverImmediately
        )
    }

    @objc private func received(_ notification: Notification) {
        guard let command = notification.object as? String else { return }
        let words = command.split(separator: " ", maxSplits: 1).map(String.init)
        guard let verb = words.first else { return }
        let rest = words.count > 1 ? words[1] : ""
        // From a timer on the run loop, not from inside this callout: Quit waits for
        // the model in a nested run loop, and from inside a callout the model's quit
        // never ran, so a `quit` left the app hung.
        let timer = Timer(timeInterval: 0, repeats: false) { [perform] _ in
            MainActor.assumeIsolated { perform(verb, rest) }
        }
        RunLoop.main.add(timer, forMode: .common)
    }
}

extension NSMenu {
    /// Chooses the item with this title, in this menu or any submenu, as a click would.
    /// Answers whether there was one.
    @discardableResult
    func performItem(titled title: String) -> Bool {
        for (index, item) in items.enumerated() {
            if item.title == title, item.isEnabled, item.action != nil {
                performActionForItem(at: index)
                return true
            }
            if let submenu = item.submenu, submenu.performItem(titled: title) { return true }
        }
        return false
    }
}
