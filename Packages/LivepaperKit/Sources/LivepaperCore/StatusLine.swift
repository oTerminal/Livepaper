import Foundation

/// Core's form of the design system's `StatusLineStatus`, which Core cannot
/// import: the app maps one to the other, case for case.
public enum StatusLineContent: Equatable, Sendable {
    case idle(String)
    case working(String)
    /// The wallpaper service has stopped answering, and Restart is offered.
    case serviceNotResponding
}

/// The status line's words.
///
/// A service that is not responding comes first, because only the user can
/// act on it, and so does what came of the user's Restart (`ServiceRestart`):
/// restarting, waiting for the service, or when Restart can next be tried,
/// said by `time`. Then an import, which takes the line while it runs; then
/// the render host's own work; then what it is showing. `showing` is how many
/// displays the render state shows, and `importing` the running import's place
/// in the list and the list's length.
public func statusLine(
    host: RenderHostStatus,
    showing: Int,
    isPausedAll: Bool,
    importing: (position: Int, count: Int)?,
    restart: ServiceRestart.Phase = .idle,
    time: (Date) -> String = { $0.formatted(date: .omitted, time: .shortened) }
) -> StatusLineContent {
    if let line = serviceLine(host: host, restart: restart, time: time) { return line }
    if let importing {
        return .working(importing.count > 1 ? "Importing \(importing.position) of \(importing.count)" : "Importing")
    }
    switch host {
    case .connecting, .recovering: return .working(host.words)
    case .notSelected, .unavailable: return .idle(host.words)
    case .stopped: return .idle(isPausedAll ? "Paused" : host.words)
    case .live: return .idle(isPausedAll ? "Paused" : liveWords(showing: showing))
    }
}

/// Whether the line says Livepaper is not the wallpaper, and so offers System
/// Settings' Wallpaper pane beside it for the user to choose it again:
/// nothing is edited when another wallpaper was picked by hand.
public func statusLineOffersWallpaperPane(
    host: RenderHostStatus, importing: (position: Int, count: Int)?, restart: ServiceRestart.Phase = .idle
) -> Bool {
    host == .notSelected && importing == nil && serviceLine(host: host, restart: restart) { _ in "" } == nil
}

/// The line while the service is not responding, or Restart is at work; nil otherwise.
private func serviceLine(host: RenderHostStatus, restart: ServiceRestart.Phase, time: (Date) -> String) -> StatusLineContent? {
    if restart == .restarting { return .working("Restarting the wallpaper service") }
    guard host == .recovering(.restartAgent) else { return nil }
    switch restart {
    case .idle, .restarting: return .serviceNotResponding
    case .waitingForAnswer: return .working("Waiting for the wallpaper service")
    case .retryFrom(let date): return .idle("Restarted recently; try again at \(time(date))")
    }
}

private func liveWords(showing: Int) -> String {
    switch showing {
    case 0: "No wallpaper set"
    case 1: "Live on 1 display"
    default: "Live on \(showing) displays"
    }
}
