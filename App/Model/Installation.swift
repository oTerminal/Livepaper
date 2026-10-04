import AppKit
import LivepaperCore
import LivepaperSystem
import Observation

/// Where Livepaper runs, decided as the app starts, before anything is
/// registered: carry on; ask for the drag to Applications, starting nothing; or
/// offer the move, starting nothing until the user answers. Onboarding waits
/// for it: its window shows this card first, and its cards once Not Now has
/// started Livepaper.
@Observable
final class Installation {
    /// Where the question has got to.
    enum Phase: Equatable {
        case asking
        /// Move failed, and why, in a sentence: the card asks again.
        case failed(String)
        /// Not Now, or nothing was asked.
        case answered
    }

    let decision: InstallDecision
    private(set) var phase: Phase

    /// Livepaper starting, as a launch that asks nothing starts it: the app
    /// delegate's, called once Not Now is answered.
    @ObservationIgnored var startLivepaper: () -> Void = {}
    @ObservationIgnored private let services: InstallServices

    init(services: InstallServices) {
        self.services = services
        let decided = installDecision(
            services.location, homeDirectory: services.homeDirectory, declinedPaths: services.declined.paths
        )
        let decision = decided == .offerMove && !services.offersMove ? .proceed : decided
        self.decision = decision
        phase = decision == .proceed ? .answered : .asking
        let words = decision == decided ? AppLog.installDecided(decision) : AppLog.installMoveNotOffered
        AppLog.logger.notice("\(words, privacy: .public)")
    }

    /// Whether the card is up and nothing has started.
    var isAsking: Bool { phase != .answered }

    // MARK: Asking for the drag

    func openApplicationsFolder() {
        services.showApplicationsFolder()
    }

    /// Nothing started, so nothing is written.
    func quit() {
        NSApp.terminate(nil)
    }

    // MARK: Offering the move

    /// Moves Livepaper to `/Applications`, opens it there once this process has
    /// exited, and quits. A failure is said on the card, which asks again.
    func move() {
        do throws(ApplicationsMoveError) {
            let moved = try services.moveToApplications()
            AppLog.logger.notice("\(AppLog.installMoved, privacy: .public)")
            services.relaunch(moved)
            NSApp.terminate(nil)
        } catch {
            AppLog.logger.error("\(AppLog.installNotMoved(error), privacy: .public)")
            phase = .failed(error.words)
        }
    }

    /// Remembers this path, so that it is not asked again, and starts Livepaper.
    func notNow() {
        services.declined.paths.insert(services.location.bundlePath)
        AppLog.logger.notice("\(AppLog.installNotNow, privacy: .public)")
        phase = .answered
        startLivepaper()
    }
}

// MARK: - What it runs on

/// Where this copy runs, what was declined, and moving it. Wired, the paths
/// declined are the app's preferences; in the fakes run they are in memory, and
/// Move and the Applications folder are logged.
struct InstallServices {
    var location: InstallLocation
    var homeDirectory: String
    var declined: any DeclinedMoveKeeping
    /// False in a Debug build, which runs from `build/` or DerivedData by design:
    /// it is never offered the move, though it is still asked for the drag.
    var offersMove = true
    var showApplicationsFolder: () -> Void
    /// Answers where Livepaper now is.
    var moveToApplications: () throws(ApplicationsMoveError) -> URL
    /// Opens the moved copy once this process has exited.
    var relaunch: (URL) -> Void

    static func wired() -> InstallServices {
        let bundle = Bundle.main.bundleURL
        return InstallServices(
            location: .current(),
            homeDirectory: URL.homeDirectory.path,
            declined: DefaultsDeclinedMove(),
            offersMove: !BuildConfiguration.isDebug,
            showApplicationsFolder: {
                guard let applications = FileManager.default.urls(for: .applicationDirectory, in: .localDomainMask).first else { return }
                NSWorkspace.shared.open(applications)
            },
            moveToApplications: { () throws(ApplicationsMoveError) -> URL in try ApplicationsMove.move(bundle) },
            relaunch: { app in
                do {
                    try ApplicationsMove.relaunch(app)
                } catch {
                    AppLog.logger.error("\(AppLog.installNotRelaunched(error), privacy: .public)")
                }
            }
        )
    }
}

/// The bundle paths the user answered Not Now for.
protocol DeclinedMoveKeeping: AnyObject {
    var paths: Set<String> { get set }
}

/// The app's preferences: `MoveDeclinedPaths`, each path Not Now was answered for.
final class DefaultsDeclinedMove: DeclinedMoveKeeping {
    static let key = "MoveDeclinedPaths"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var paths: Set<String> {
        get { Set(defaults.stringArray(forKey: Self.key) ?? []) }
        set { defaults.set(newValue.sorted(), forKey: Self.key) }
    }
}

final class InMemoryDeclinedMove: DeclinedMoveKeeping {
    var paths: Set<String> = []
}
