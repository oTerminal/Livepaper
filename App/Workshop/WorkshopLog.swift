import Foundation
import LivepaperSystem
import LivepaperWorkshop
import os

/// The Workshop's log lines, under `LivepaperSystem.logSubsystem`, category
/// `workshop`. No line holds a password or a code, and none names the account:
/// steamcmd's own lines, which do, are kept at debug level and private.
enum WorkshopLog {
    static let category = "workshop"

    static let logger = Logger(subsystem: LivepaperSystem.logSubsystem, category: category)

    /// steamcmd's lines arrive on the thread that reads its terminal, so their
    /// logger is its own. The subsystem is `LivepaperSystem.logSubsystem`'s.
    nonisolated private static let steamcmdLogger = Logger(subsystem: "app.livepaper.Livepaper", category: "workshop")

    /// A line steamcmd printed. Nothing typed is among them: its terminal does not echo.
    @Sendable nonisolated static func steamcmd(_ line: String) {
        steamcmdLogger.debug("steamcmd: \(line, privacy: .private)")
    }

    static func settingUp() -> String {
        "workshop: setting up steamcmd from \(SteamCmdTool.archive.absoluteString)"
    }

    static let setUp = "workshop: steamcmd set up, Valve's signature checked"

    static func getting(_ item: WorkshopItemID) -> String {
        "workshop: getting item \(item)"
    }

    static func downloaded(_ item: WorkshopItemID, bytes: Int64) -> String {
        "workshop: item \(item) downloaded, \(bytes) bytes"
    }

    static func handedOver(_ item: WorkshopItemID) -> String {
        "workshop: item \(item) handed to the import"
    }

    static func notGot(_ item: WorkshopItemID, _ error: any Error) -> String {
        "workshop: item \(item) not got: \(error)"
    }

    static func refused(_ item: WorkshopItemID, _ problem: WorkshopProblem) -> String {
        "workshop: item \(item) refused: \(problem)"
    }

    static let signingIn = "workshop: signing in to Steam"
    static let signedIn = "workshop: signed in to Steam; steamcmd saved its login"

    static func signInFailed(_ error: any Error) -> String {
        "workshop: sign-in failed: \(error)"
    }

    static let signInCancelled = "workshop: sign-in cancelled"
    static let signedOut = "workshop: signed out of Steam; steamcmd's saved login revoked"

    static func signOutFailed(_ error: any Error) -> String {
        "workshop: sign-out failed: \(error)"
    }
}
