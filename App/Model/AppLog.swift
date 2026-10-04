import Foundation
import LivepaperCore
import LivepaperImport
import LivepaperSystem
import os

/// The app model's log lines, under `LivepaperSystem.logSubsystem`, category
/// `app`. The checks on screen and the manual script are read against them.
///
/// The newer lines never hold a path, a user name or a source file's name: a
/// command is logged by IDs, an error by its kind (`LogWords`), the socket by
/// its folder. The older lines that name a wallpaper keep their own convention.
enum AppLog {
    static let category = "app"

    static let logger = Logger(subsystem: LivepaperSystem.logSubsystem, category: category)

    static func launched(fakes: Bool) -> String {
        "app: launched \(fakes ? "on fakes" : "wired")"
    }

    // MARK: Where Livepaper runs

    static let installMoveNotOffered = "install: outside Applications, but a Debug build is not offered the move; starting"

    static func installDecided(_ decision: InstallDecision) -> String {
        switch decision {
        case .proceed: "install: in Applications, or Not Now was answered here; starting"
        case .askForDrag:
            "install: run from the disk image or translocated, asking for the drag to Applications; "
                + "no library, host, sensors, hotkeys or socket, and nothing registered or written"
        case .offerMove: "install: outside Applications, offering the move; nothing starts until it is answered"
        }
    }

    static let installMoved = "install: moved to /Applications, opening it there once this process has exited"

    static func installNotMoved(_ error: ApplicationsMoveError) -> String {
        switch error {
        case .openThere: "install: not moved: a Livepaper in Applications is open"
        case .notPermitted: "install: not moved: Applications cannot be written"
        case .noSpace: "install: not moved: no space"
        case .failed(let kind): "install: not moved: \(kind)"
        }
    }

    static func installNotRelaunched(_ error: any Error) -> String {
        "install: moved, but not opened from Applications: \(LogWords.kind(of: error))"
    }

    static let installNotNow = "install: Not Now, remembered for this path; starting Livepaper"

    static func doorHeld(_ count: Int) -> String {
        "door: \(count) \(count == 1 ? "item" : "items") handed over before Livepaper started, held until it does"
    }

    static let notStarted = "app: a change refused: Livepaper was not started, so it writes nothing"

    static func swept(_ count: Int) -> String {
        "app: swept \(count) interrupted imports"
    }

    static func sweepFailed(_ error: any Error) -> String {
        "app: sweeping interrupted imports failed: \(error)"
    }

    static func libraryUnreadable(_ error: any Error) -> String {
        "app: library not read, so nothing will be written: \(error)"
    }

    static func stateKeptAside(at url: URL, version: SchemaVersion?) -> String {
        "app: app state kept aside at \(url.path) (version \(version?.description ?? "unreadable")), starting on defaults"
    }

    static func renderStateUnreadable(_ error: any Error) -> String {
        "app: render state on disk not read: \(error)"
    }

    static func activationFailed(_ error: any Error) -> String {
        "app: host not activated: \(error)"
    }

    static func applied(_ state: RenderState) -> String {
        "app: render state \(state.generation) made, \(state.displays.count) displays showing"
    }

    static func librarySaveFailed(_ error: any Error) -> String {
        "app: library not saved, so the change was not made: \(error)"
    }

    static func stateSaveFailed(_ error: any Error) -> String {
        "app: app state not saved; it holds until quit: \(error)"
    }

    static func pausedAll(generation: UInt64?) -> String {
        "app: pause all, render state \(generation.map(String.init) ?? "none") pauses every display"
    }

    static let resumedAll = "app: resume all"

    static func importFinished(_ wallpaper: Wallpaper) -> String {
        "app: import finished, wallpaper \(wallpaper.id) \"\(wallpaper.name)\""
    }

    static func importDuplicate(of wallpaper: Wallpaper) -> String {
        "app: import finished, duplicate of wallpaper \(wallpaper.id) \"\(wallpaper.name)\""
    }

    static func importFailed(_ name: String, _ error: any Error) -> String {
        "app: import failed for \"\(name)\": \(error)"
    }

    static func deleted(_ wallpaper: Wallpaper) -> String {
        "app: deleted wallpaper \(wallpaper.id) \"\(wallpaper.name)\", undo offered"
    }

    static func undone(_ wallpaper: Wallpaper) -> String {
        "app: delete of wallpaper \(wallpaper.id) undone"
    }

    static func trashed(_ id: WallpaperID) -> String {
        "app: wallpaper \(id)'s folder moved to the Trash"
    }

    static func trashFailed(_ id: WallpaperID, _ error: any Error) -> String {
        "app: wallpaper \(id)'s folder not moved to the Trash; the next launch's sweep takes it: \(error)"
    }

    static func quit(lastGeneration: UInt64?) -> String {
        "app: quit, stopped after render state \(lastGeneration.map(String.init) ?? "none")"
    }

    static func scenePrepared(_ id: WallpaperID, programs: Int, failures: Int) -> String {
        "scene: prepared \(id), \(programs) programs, \(failures) failed"
    }

    static func sceneNotPrepared(_ id: WallpaperID, reason: String) -> String {
        "scene: \(id) not prepared: \(reason)"
    }

    /// A scene's preparation, at import or at launch: a notice when its programs
    /// were written, an error when they were not and it holds its poster.
    static func log(_ preparation: ScenePreparation.Outcome, of id: WallpaperID) {
        switch preparation {
        case .prepared(let programs, let failures):
            logger.notice("\(scenePrepared(id, programs: programs, failures: failures), privacy: .public)")
        case .notPrepared(let reason):
            logger.error("\(sceneNotPrepared(id, reason: reason), privacy: .public)")
        }
    }

    static func scenePosterDrawn(_ id: WallpaperID, width: Int, height: Int) -> String {
        "scene: poster of \(id) drawn from the scene, \(width)x\(height) at \(Int(ScenePoster.time)) s"
    }

    static func scenePosterNotDrawn(_ id: WallpaperID, reason: String) -> String {
        "scene: poster of \(id) not drawn from the scene, so it is the preview's: \(reason)"
    }

    /// How a scene's poster was made, at import or at launch: a notice when it
    /// was drawn from the scene, an error when it is still the item's preview.
    static func log(_ poster: ScenePoster.Outcome, of id: WallpaperID) {
        switch poster {
        case .drawn(let width, let height):
            logger.notice("\(scenePosterDrawn(id, width: width, height: height), privacy: .public)")
        case .notDrawn(let reason):
            logger.error("\(scenePosterNotDrawn(id, reason: reason), privacy: .public)")
        }
    }

    static func choosingFiles(asSheet: Bool) -> String {
        "app: choosing files to import, \(asSheet ? "in a sheet on the library window" : "in a panel of its own")"
    }

    // MARK: The doors and their commands

    static func words(for door: EntryPoint) -> String {
        switch door {
        case .urlScheme: "a livepaper:// link"
        case .commandSocket: "the command socket"
        }
    }

    /// Files LaunchServices handed over, from `open -a` or wherever, by count.
    static func filesLeft(_ count: Int) -> String {
        "door: \(count) \(count == 1 ? "file" : "files") handed over and left: importing is done in the app's window"
    }

    /// By its kind: anything can open a link, and what it carried can name a path.
    static func linkRefused(_ rejection: CommandRejection) -> String {
        "door: livepaper:// link refused: \(rejection.kind)"
    }

    static func command(_ command: Command, from door: EntryPoint) -> String {
        "command: \(summary(of: command)) from \(words(for: door))"
    }

    static func commandDone(_ command: Command) -> String {
        "command: \(command.verb.rawValue) done"
    }

    /// A refusal's words name IDs and displays by UUID, never a file.
    static func commandRefused(_ command: Command, _ refusal: CommandRefusal) -> String {
        "command: \(command.verb.rawValue) refused: \(refusal.reason)"
    }

    /// The command by IDs, never by names.
    static func summary(of command: Command) -> String {
        func target(_ target: DisplayTarget) -> String {
            switch target {
            case .all: "all displays"
            case .display(let display): "display \(display)"
            }
        }
        return switch command {
        case .set(.wallpaper(let id), let on): "set wallpaper \(id) on \(target(on))"
        case .set(.playlist(let id), let on): "set playlist \(id) on \(target(on))"
        case .pause(let on), .resume(let on), .next(let on): "\(command.verb.rawValue) \(target(on))"
        case .mute, .unmute, .library, .settings, .diagnostics, .status: command.verb.rawValue
        }
    }

    static func socketOpened(at socket: URL) -> String {
        "socket: listening, in \(LibraryLocation.commandSocketFolder(of: socket))"
    }

    static func socketNotOpened(_ error: any Error) -> String {
        "socket: not opened, so the livepaper tool cannot reach this run: \(LogWords.kind(of: error))"
    }

    static let socketClosed = "socket: closed"

    static let diagnosticsCopied = "diagnostics: report copied"
    static let diagnosticsSaved = "diagnostics: report saved"

    static func diagnosticsNotSaved(_ error: any Error) -> String {
        "diagnostics: report not saved: \(LogWords.kind(of: error))"
    }

    // MARK: Restart

    static let restartAsked = "app: Restart clicked, asking the host to restart WallpaperAgent"

    static func restartAnswered(_ phase: ServiceRestart.Phase) -> String {
        switch phase {
        case .waitingForAnswer: "app: WallpaperAgent restarted, waiting for the service to answer"
        case .retryFrom(let date): "app: restart refused, Restart can be tried again from \(date.formatted(.iso8601))"
        case .idle, .restarting: "app: restart asked for, and the host recorded none"
        }
    }
}
