import Observation
import Sparkle
import SwiftUI

/// Updates through Sparkle 2, in Sparkle's own windows. The feed, the EdDSA
/// key, the daily check and the click an install waits for are the Info.plist's
/// (`project.yml`). The app is not sandboxed, so Sparkle installs without its XPC
/// services.
///
/// The updater starts with Livepaper, never while the first launch asks where it
/// runs, never on fakes, and never in a Debug build: a build from `build/` is not
/// what the feed's releases replace.
@Observable
final class Updates {
    /// Whether Check for Updates can run now: the updater started, and no check under way.
    private(set) var canCheck = false

    @ObservationIgnored private let controller = SPUStandardUpdaterController(
        startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil
    )
    @ObservationIgnored private let isEnabled: Bool
    @ObservationIgnored private var watch: NSKeyValueObservation?

    init(options: LaunchOptions) {
        isEnabled = !options.isFakes && !BuildConfiguration.isDebug
    }

    func start() {
        guard isEnabled else { return }
        controller.startUpdater()
        // Sparkle changes it on the main thread.
        watch = controller.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] _, change in
            guard let canCheck = change.newValue else { return }
            MainActor.assumeIsolated { self?.canCheck = canCheck }
        }
    }

    func checkForUpdates() {
        guard canCheck else { return }
        controller.checkForUpdates(nil)
    }
}

/// "Check for Updates…" in the app menu, dimmed while it cannot run.
struct CheckForUpdatesCommand: View {
    let updates: Updates

    var body: some View {
        Button("Check for Updates…") { updates.checkForUpdates() }
            .disabled(!updates.canCheck)
    }
}
