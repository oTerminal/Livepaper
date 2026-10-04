import Foundation

/// What steamcmd is started for.
public enum SteamJob: Equatable, Sendable {
    /// Sign in with a password and whatever Steam Guard asks, so that steamcmd saves a login.
    case signIn(account: String)
    /// Download a Wallpaper Engine Workshop item with the saved login, never a password.
    case download(WorkshopItemID, account: String)
    /// Revoke the saved login (steamcmd's `logout`).
    case signOut(account: String)
    /// Let a steamcmd just set up fetch the rest of itself, then quit.
    case update
}

/// How a job is getting on, for the screens.
public enum SteamProgress: Equatable, Sendable {
    /// steamcmd checking or fetching an update of itself; `percent` is nil when it does not say.
    case updating(percent: Int?)
    case signingIn
    /// Waiting for the user to approve the sign-in in the Steam Mobile app.
    case waitingForApproval
    case downloading
    case signingOut
}

/// What a job that worked did.
public enum SteamOutcome: Equatable, Sendable {
    case signedIn
    /// The item's folder, as steamcmd names it, and its size.
    case downloaded(folder: String, bytes: Int64)
    case signedOut
    case updated
}

/// Whether a name is one Steam could give an account: letters, digits and
/// underscores, 64 at most. Nothing else is ever typed after `login`, so a name
/// cannot carry a second command, or a password, into the console.
public func isSteamAccountName(_ name: String) -> Bool {
    (1...64).contains(name.count) && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
}

/// What to type into steamcmd's console, and when, for one job: a pure reducer
/// over the lines steamcmd prints (`SteamLine`), table-tested.
///
/// It types a command only at the `Steam>` prompt, since steamcmd drops what is
/// typed ahead of it. The password and a Steam Guard code are never in it: it
/// says when to type them (`typePassword`, `askForCode`), and the driver, which
/// holds them for the one sign-in, types them. A download or a sign-out never
/// answers a password or code prompt: that means the saved login has gone.
///
/// steamcmd forgets a login at `logout` but writes that down only when it quits
/// (seen on 2026-09-24: stopped at a prompt after `logout`, it kept the revoked
/// login, and the next sign-in was refused with it, "Access Denied", before any
/// password was asked for). So a `logout` is always followed by `quit`, and the
/// job goes on in a new run: a sign-out proves the login gone, and a sign-in
/// that met a saved login Steam refuses asks for the password.
public struct SteamConversation: Equatable, Sendable {
    public enum Effect: Equatable, Sendable {
        /// A console command, typed with a line ending.
        case type(String)
        /// The password, typed at its prompt with echo off.
        case typePassword
        /// Ask the user for a Steam Guard code and type it. `again` when the one before was refused.
        case askForCode(SteamGuard, again: Bool)
        case report(SteamProgress)
        /// How the job ended. What follows is `type("quit")` at the next prompt, or `stop`.
        case finish(Result<SteamOutcome, WorkshopError>)
        /// End steamcmd now: it waits at a prompt Livepaper will not answer.
        case stop
        /// steamcmd restarted itself after updating: start it again with the same job.
        case restart
    }

    private enum Phase: Equatable, Sendable {
        case starting
        case signingIn(SignIn)
        case signedIn
        case downloading
        /// Steam refused the saved login: `logout` goes at the next prompt.
        case forgettingSavedLogin
        /// `logout` typed: `quit` goes at the next prompt, so that steamcmd writes it down.
        case loggedOut
        /// `quit` typed after `logout`: once steamcmd has gone, it is started again.
        case leavingLoggedOut
        /// `login` typed in the run after `logout`: only the saved login seen to be gone is a sign-out.
        case confirmingSignOut
        /// Finished: `quit` goes at the next prompt.
        case closing
        case quitting
    }

    /// How far a sign-in has got.
    private struct SignIn: Equatable, Sendable {
        var passwordTyped = false
        var codesAsked = 0
        var approvalSaid = false
        /// steamcmd said it signs in with its saved login, and nothing has been typed since.
        var savedLoginTried = false
    }

    public let job: SteamJob
    private var phase = Phase.starting
    private var signedIn = false
    /// steamcmd has quit after a `logout`, so it has no saved login for the account any more.
    private var hasQuitAfterLogout = false

    public init(job: SteamJob) {
        self.job = job
    }

    /// The job has an answer; all that is left is for steamcmd to go.
    public var isFinished: Bool {
        phase == .closing || phase == .quitting
    }

    public mutating func read(_ line: SteamLine) -> [Effect] {
        if case .updating(let percent) = line, !isFinished {
            return [.report(.updating(percent: percent))]
        }
        switch phase {
        case .starting: return start(line)
        case .signingIn: return signingIn(line)
        case .signedIn: return signedIn(line)
        case .downloading: return downloading(line)
        case .forgettingSavedLogin, .loggedOut, .leavingLoggedOut: return loggingOut(line)
        case .confirmingSignOut: return confirmingSignOut(line)
        case .closing:
            guard line == .console else { return [] }
            phase = .quitting
            return [.type("quit")]
        case .quitting: return []
        }
    }

    /// steamcmd ended. Before the job had an answer that is a failure, unless it restarted itself after an update.
    public mutating func exited(status: Int32) -> [Effect] {
        guard !isFinished else { return [] }
        if phase == .leavingLoggedOut, status == 0 {
            // It has written the login down as gone: the job goes on in a new run.
            phase = .starting
            hasQuitAfterLogout = true
            return [.restart]
        }
        if status == 42 {
            // steamcmd.sh's MAGIC_RESTART_EXITCODE: it updated itself and wants to run again.
            phase = .starting
            signedIn = false
            return [.restart]
        }
        phase = .quitting
        return [.finish(.failure(.toolStopped(status: status)))]
    }

    // MARK: Phases

    private mutating func start(_ line: SteamLine) -> [Effect] {
        guard line == .console else { return [] }
        let account: String
        let progress: SteamProgress
        switch job {
        case .update:
            return finish(.success(.updated), then: .type("quit"))
        case .signIn(let name):
            account = name
            progress = .signingIn
        case .download(_, let name):
            account = name
            progress = .signingIn
        case .signOut(let name):
            account = name
            progress = .signingOut
        }
        guard isSteamAccountName(account) else { return finish(.failure(.notAnAccountName), then: .type("quit")) }
        if hasQuitAfterLogout, case .signOut = job {
            phase = .confirmingSignOut
            return [.type("login \(account)")]
        }
        phase = .signingIn(SignIn())
        return [.type("login \(account)"), .report(progress)]
    }

    private mutating func signingIn(_ line: SteamLine) -> [Effect] {
        guard case .signingIn(var signIn) = phase else { return [] }
        switch line {
        case .passwordPrompt, .codePrompt:
            return prompted(line, signIn)
        case .awaitingApproval:
            guard !signIn.approvalSaid else { return [] }
            signIn.approvalSaid = true
            phase = .signingIn(signIn)
            return [.report(.waitingForApproval)]
        case .savedLogin:
            signIn.savedLoginTried = true
            phase = .signingIn(signIn)
            return []
        case .signInFailed(let result):
            let error = WorkshopError(signInResult: result)
            guard signIn.savedLoginTried, !error.isAboutReachingSteam else { return finish(.failure(error), then: nil) }
            return savedLoginRefused(error)
        case .signedIn:
            signedIn = true
            phase = .signedIn
            return []
        case .console:
            // Back at the prompt with neither a sign-in nor Steam's reason.
            return finish(.failure(.noAnswer), then: .type("quit"))
        default:
            return []
        }
    }

    /// A password or Steam Guard prompt. Only a sign-in answers one: anything
    /// else would try a password it does not have.
    private mutating func prompted(_ line: SteamLine, _ signIn: SignIn) -> [Effect] {
        switch job {
        case .signIn: break
        case .signOut: return finish(.success(.signedOut), then: .stop)
        case .download, .update: return finish(.failure(.signInNeeded), then: .stop)
        }
        var next = signIn
        next.savedLoginTried = false
        if case .codePrompt(let kind) = line {
            next.codesAsked += 1
            phase = .signingIn(next)
            return [.askForCode(kind, again: signIn.codesAsked > 0)]
        }
        guard !signIn.passwordTyped else { return finish(.failure(.wrongPassword), then: .stop) }
        next.passwordTyped = true
        phase = .signingIn(next)
        return [.typePassword]
    }

    /// Steam refused the saved login steamcmd tried, which it keeps until it is logged out of
    /// (seen: the one a sign-out left behind). A download cannot sign in, so it asks for a
    /// sign-in; a sign-in or a sign-out logs out of it, once.
    private mutating func savedLoginRefused(_ error: WorkshopError) -> [Effect] {
        switch job {
        case .download: return finish(.failure(.signInNeeded), then: nil)
        case .signIn where hasQuitAfterLogout, .update: return finish(.failure(error), then: nil)
        case .signIn, .signOut:
            phase = .forgettingSavedLogin
            return []
        }
    }

    private mutating func signedIn(_ line: SteamLine) -> [Effect] {
        guard line == .console else { return [] }
        switch job {
        case .signIn, .update:
            return finish(.success(.signedIn), then: .type("quit"))
        case .download(let item, _):
            phase = .downloading
            return [.type("workshop_download_item \(wallpaperEngineApp) \(item)"), .report(.downloading)]
        case .signOut:
            phase = .loggedOut
            return [.type("logout")]
        }
    }

    /// `logout` at the next prompt, then `quit` at the one after, so that steamcmd writes
    /// the login down as gone. Back at the prompt says nothing of whether it worked: the
    /// next run tries the login again, and steamcmd asking for the password is the proof.
    private mutating func loggingOut(_ line: SteamLine) -> [Effect] {
        // After `quit`, what steamcmd says on its way out.
        guard line == .console, phase != .leavingLoggedOut else { return [] }
        if phase == .forgettingSavedLogin {
            phase = .loggedOut
            return [.type("logout")]
        }
        phase = .leavingLoggedOut
        return [.type("quit")]
    }

    private mutating func confirmingSignOut(_ line: SteamLine) -> [Effect] {
        switch line {
        case .noSavedLogin, .passwordPrompt, .codePrompt:
            return finish(.success(.signedOut), then: .stop)
        case .savedLogin, .signedIn:
            return finish(.failure(.stillSignedIn), then: nil)
        case .signInFailed(let result):
            return finish(.failure(WorkshopError(signInResult: result)), then: nil)
        case .console:
            return finish(.failure(.noAnswer), then: .type("quit"))
        default:
            return []
        }
    }

    private mutating func downloading(_ line: SteamLine) -> [Effect] {
        guard case .download(let item, _) = job else { return [] }
        switch line {
        case .downloaded(item, let folder, let bytes):
            return finish(.success(.downloaded(folder: folder, bytes: bytes)), then: nil)
        case .downloadFailed(item, let reason), .downloadFailed(nil, let reason):
            return finish(.failure(WorkshopError(downloadResult: reason)), then: nil)
        case .console:
            return finish(.failure(.noAnswer), then: .type("quit"))
        default:
            return []
        }
    }

    /// The answer, then how steamcmd is to go: typed `quit` now, stopped now, or (nil) `quit` at the next prompt.
    private mutating func finish(_ result: Result<SteamOutcome, WorkshopError>, then ending: Effect?) -> [Effect] {
        switch ending {
        case .type:
            phase = .quitting
        case .stop:
            phase = .quitting
        default:
            phase = .closing
        }
        return [.finish(result)] + (ending.map { [$0] } ?? [])
    }
}
