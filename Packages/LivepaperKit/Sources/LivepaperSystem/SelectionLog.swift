import Foundation
import LivepaperCore

/// The wording of Selection's log lines, under `LivepaperSystem.logSubsystem`, category
/// `selection`. The onboarding check and the beta-seed checklist read them. None names a
/// file or a path.
nonisolated public enum SelectionLog {
    public static let category = "selection"

    public static func selecting(host: RenderHostStatus) -> String {
        "selection: selecting Livepaper, host \(host.name)"
    }

    public static let leaving = "selection: leaving Livepaper"

    public static func listed(_ listed: Bool) -> String {
        listed ? "selection: pluginkit lists the extension" : "selection: pluginkit does not list the extension"
    }

    public static func selected(_ edit: WallpaperStoreEdit) -> String {
        guard edit.wrote else {
            return "selection: store already names Livepaper in all \(edit.desktopEntries) Desktop entries, nothing written"
        }
        return "selection: store written, \(edit.changed) of \(edit.desktopEntries) Desktop entries now name Livepaper"
            + (edit.keptCopy ? "; the store as it was kept" : "")
    }

    public static func deselected(_ edit: WallpaperStoreEdit) -> String {
        edit.wrote
            ? "selection: store written, \(edit.changed) Desktop entries put back from the kept copy"
            : "selection: store names Livepaper nowhere, nothing written"
    }

    public static let restarting = "selection: restarting WallpaperAgent"

    public static func restarted(_ outcome: AgentRestartOutcome) -> String {
        switch outcome {
        case .restarted(let previous, let current): "selection: WallpaperAgent restarted, pid \(previous) -> \(current)"
        case .notBack(let previous): "selection: WallpaperAgent pid \(previous) signalled, not back yet"
        case .notRunning: "selection: WallpaperAgent is not running, nothing to restart"
        case .signalFailed(let pid, let errno): "selection: could not signal WallpaperAgent pid \(pid), errno \(errno)"
        }
    }

    public static func live(after: Duration) -> String {
        "selection: live \(String(format: "%.2f", after.timeInterval)) s after asking"
    }

    public static let alreadyLive = "selection: already live, nothing written"

    public static func fallback(_ why: SelectionFallback) -> String {
        "selection: opening System Settings at Wallpaper: \(reason(why))"
    }

    public static let paneNotOpened = "selection: System Settings could not be opened"

    public static let keptCopyRemoved = "selection: kept copy removed"

    static func reason(_ why: SelectionFallback) -> String {
        switch why {
        case .notListed: "pluginkit does not list the extension"
        case .noLiveInTime: "no heartbeat with a desktop surface within \(Int(SelectionReducer.wait.timeInterval)) s"
        case .store(let error): reason(error)
        }
    }

    static func reason(_ error: WallpaperStoreError) -> String {
        switch error {
        case .unreadable(let file): "\(name(of: file)) is missing or unreadable"
        case .unknownShape(let file, let problem): "\(name(of: file)) is of a shape this build does not know (\(words(problem)))"
        case .notWritten(let file): "\(name(of: file)) could not be written"
        case .noKeptCopy: "no copy of the store was kept"
        case .nothingToGoBackTo: "the kept copy has no wallpaper of its own to go back to"
        }
    }

    private static func name(of file: WallpaperStoreFile) -> String {
        switch file {
        case .store: "the wallpaper store"
        case .keptCopy: "the kept copy of the store"
        }
    }

    private static func words(_ problem: WallpaperStoreProblem) -> String {
        switch problem {
        case .notADictionary: "not a dictionary"
        case .noPlaces: "none of the places"
        case .unexpected(let at): "unexpected at \(at)"
        }
    }
}
