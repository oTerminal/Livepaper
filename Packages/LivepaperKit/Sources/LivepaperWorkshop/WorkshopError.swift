import Foundation

/// Why getting a Workshop item, signing in or signing out did not work. Steam's
/// own results are read into the cases Livepaper can say something useful
/// about; the rest keep Steam's words (`steamSaid`).
public enum WorkshopError: Error, Equatable, Sendable {
    // MARK: Steam's answers

    /// `Invalid Password`, which Steam also says for an account name it does not have.
    case wrongPassword
    /// A Steam Guard code Steam did not take: wrong, or expired.
    case wrongCode
    /// Too many sign-ins from this Mac for a while.
    case rateLimited
    case timedOut
    case noConnection
    /// There is no saved login to download with: the user has not signed in, or the login was revoked or expired.
    case signInNeeded
    /// Steam would not give the item to this account. An account that does not own
    /// Wallpaper Engine is told `Failure` (seen with an anonymous login on 2026-09-23).
    case notOwned
    /// Steam has no item of that number, or no longer has it.
    case itemNotFound
    /// steamcmd's `logout` did not take the saved login back: signing in again needed no password.
    case stillSignedIn
    /// Any other result, in Steam's words.
    case steamSaid(String)

    // MARK: Livepaper's side

    /// Not a name Steam could give an account, so it is never typed.
    case notAnAccountName
    /// The item's page says it belongs to another app's Workshop.
    case notWallpaperEngine
    /// steamcmd is an Intel program, and Rosetta is not installed.
    case rosettaMissing
    /// The downloaded steamcmd does not carry Valve's signature, so it is never run.
    case toolUntrusted
    /// steamcmd could not be fetched from Valve.
    case toolNotDownloaded
    /// steamcmd is there but the system would not start it.
    case toolNotStarted
    /// steamcmd ended by itself before the job had an answer.
    case toolStopped(status: Int32)
    /// steamcmd went back to its console without saying how the job went.
    case noAnswer
    /// steamcmd said it downloaded the item, and discovery found nothing in its folder.
    case nothingToImport

    /// A result steamcmd printed for a sign-in: `ERROR (<result>)`.
    public init(signInResult result: String) {
        switch result.lowercased() {
        case "invalid password": self = .wrongPassword
        case "two-factor code mismatch", "invalid login auth code", "expired login auth code": self = .wrongCode
        case "rate limit exceeded", "account login denied throttle", "limit exceeded": self = .rateLimited
        case "timeout": self = .timedOut
        case "no connection", "service unavailable", "try another cm", "connect failed": self = .noConnection
        default: self = .steamSaid(result)
        }
    }

    /// Steam could not be asked, or asked to be left alone for a while: nothing it said is about the login itself.
    var isAboutReachingSteam: Bool {
        switch self {
        case .noConnection, .timedOut, .rateLimited: true
        default: false
        }
    }

    /// A result steamcmd printed for a download: `ERROR! Download item <id> failed (<result>).`
    public init(downloadResult result: String) {
        switch result.lowercased() {
        case "file not found": self = .itemNotFound
        case "failure", "access denied": self = .notOwned
        case "timeout": self = .timedOut
        case "no connection", "service unavailable": self = .noConnection
        case "rate limit exceeded", "limit exceeded": self = .rateLimited
        default: self = .steamSaid(result)
        }
    }
}

/// What the Workshop's screens say when something did not work, in the house
/// voice: a whole sentence without its full stop, as `importFailureWords` gives
/// it, and what would help.
public struct WorkshopFailureWords: Equatable, Sendable {
    public let reason: String
    /// Trying again as it is may work.
    public let canRetry: Bool
    /// Signing in is what would help.
    public let needsSignIn: Bool

    public init(reason: String, canRetry: Bool, needsSignIn: Bool) {
        self.reason = reason
        self.canRetry = canRetry
        self.needsSignIn = needsSignIn
    }

    /// The same thing would fail the same way again.
    public static func final(_ reason: String) -> Self { Self(reason: reason, canRetry: false, needsSignIn: false) }
    /// Something outside Livepaper, which may be different next time.
    public static func retryable(_ reason: String) -> Self { Self(reason: reason, canRetry: true, needsSignIn: false) }
    /// The account, its password or its code.
    public static func signIn(_ reason: String) -> Self { Self(reason: reason, canRetry: false, needsSignIn: true) }
}

public func workshopFailureWords(_ error: WorkshopError) -> WorkshopFailureWords {
    accountWords(error) ?? steamWords(error) ?? toolWords(error)
}

/// Steam's answers about the account: signing in and out.
private func accountWords(_ error: WorkshopError) -> WorkshopFailureWords? {
    switch error {
    case .wrongPassword: .signIn("Steam did not accept that account name and password")
    case .wrongCode: .signIn("Steam did not accept that code. Codes last a short while, so use the newest one")
    case .rateLimited: .retryable("Steam has had too many sign-ins from this Mac. Wait a while, then try again")
    case .signInNeeded: .signIn("Livepaper is not signed in to Steam")
    case .stillSignedIn: .retryable("Steam still signed in without a password, so the saved login was not taken back")
    default: nil
    }
}

/// Steam's other answers.
private func steamWords(_ error: WorkshopError) -> WorkshopFailureWords? {
    switch error {
    case .timedOut: .retryable("Steam did not answer in time")
    case .noConnection: .retryable("Steam could not be reached. Check the Mac is online")
    case .notOwned:
        .final(
            "Steam would not give it to this account. "
                + "Wallpaper Engine’s Workshop items download only for an account that owns Wallpaper Engine"
        )
    case .itemNotFound: .final("Steam has no such Workshop item. It may have been taken down")
    case .steamSaid(let result): .retryable("Steam answered “\(result)”")
    default: nil
    }
}

/// Livepaper's side: the account name, the page, and steamcmd itself.
private func toolWords(_ error: WorkshopError) -> WorkshopFailureWords {
    switch error {
    case .notAnAccountName: .signIn("A Steam account name is made of letters, digits and underscores")
    case .notWallpaperEngine: .final("It is a Workshop item for another game, not for Wallpaper Engine")
    case .rosettaMissing:
        .retryable(
            "Steam’s download tool is made for Intel Macs and needs Rosetta, which is not installed. "
                + "Install it with “softwareupdate --install-rosetta” in Terminal, then try again"
        )
    case .toolUntrusted: .final("Steam’s download tool did not carry Valve’s signature, so Livepaper did not run it")
    case .toolNotDownloaded: .retryable("Steam’s download tool could not be fetched from Valve")
    case .toolNotStarted: .retryable("Steam’s download tool could not be started")
    case .toolStopped: .retryable("Steam’s download tool stopped before it finished")
    case .noAnswer: .retryable("Steam’s download tool ended without saying whether it worked")
    case .nothingToImport: .final("Steam downloaded it, but its folder holds nothing Livepaper can import")
    // Steam's answers, which `steamWords` has.
    default: .retryable("Steam’s download tool could not do it")
    }
}
