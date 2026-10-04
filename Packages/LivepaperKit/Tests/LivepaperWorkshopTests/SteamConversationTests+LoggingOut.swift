import Foundation
import Testing
import LivepaperWorkshop

/// Logging out: of a saved login Steam refuses, and when signing out. steamcmd writes a
/// `logout` down only when it quits, so each is followed by `quit` and a second run.
extension SteamConversationTests {
    // MARK: A saved login Steam refuses

    /// A saved login steamcmd tried and Steam refused, then back at the console: whether it is logged out of.
    static let savedLoginRefusals: [Row<String, [Effect]>] = [
        Row("seen after a sign-out stopped at a prompt: the revoked login", "Access Denied", [.type("logout")]),
        Row("a login Steam no longer takes", "Invalid Password", [.type("logout")]),
        Row("anything else Steam says of the login", "Expired Login Auth Code", [.type("logout")]),
        Row("no network: the login may be fine", "No Connection", [.finish(.failure(.noConnection)), .type("quit")]),
        Row("Steam not answering", "Timeout", [.finish(.failure(.timedOut)), .type("quit")]),
        Row("too many tries", "Rate Limit Exceeded", [.finish(.failure(.rateLimited)), .type("quit")]),
    ]

    @Test(arguments: savedLoginRefusals)
    func `a sign-in logs out of a saved login Steam refuses, but not of one it could not ask about`(row: Row<String, [Effect]>) {
        let effects = Self.talk(.signIn(account: "someone"), [.console, .savedLogin, .signInFailed(row.input), .console])
        let expected: [Effect] = [.type("login someone"), .report(.signingIn)] + row.expected
        #expect(effects == expected)
    }

    @Test func `a refused saved login is logged out of, written down by quitting, and the password asked for`() {
        let effects = Self.talk(.signIn(account: "someone"), runs: [
            [.console, .savedLogin, .signInFailed("Access Denied"), .console, .other, .console, .other],
            [.console, .noSavedLogin, .passwordPrompt, .signedIn, .console],
        ])
        let expected: [Effect] = [
            .type("login someone"), .report(.signingIn), .type("logout"), .type("quit"), .restart,
            .type("login someone"), .report(.signingIn), .typePassword,
            .finish(.success(.signedIn)), .type("quit"),
        ]
        #expect(effects == expected)
    }

    @Test func `a saved login refused again after logging out of it ends the sign-in`() {
        let refused: [SteamLine] = [.console, .savedLogin, .signInFailed("Access Denied"), .console]
        let effects = Self.talk(.signIn(account: "someone"), runs: [refused + [.console], refused])
        #expect(Array(effects.suffix(2)) == [.finish(.failure(.steamSaid("Access Denied"))), .type("quit")])
    }

    @Test func `a download whose saved login Steam refuses asks to sign in`() {
        let effects = Self.talk(.download(Self.lonelyCat, account: "someone"), [
            .console, .savedLogin, .signInFailed("Access Denied"), .console,
        ])
        #expect(effects == [.type("login someone"), .report(.signingIn), .finish(.failure(.signInNeeded)), .type("quit")])
    }

    @Test func `a password Steam denies is not a saved login to log out of`() {
        let effects = Self.talk(.signIn(account: "someone"), [.console, .passwordPrompt, .signInFailed("Access Denied"), .console])
        #expect(Array(effects.suffix(2)) == [.finish(.failure(.steamSaid("Access Denied"))), .type("quit")])
    }

    // MARK: Signing out

    /// steamcmd forgets a login at `logout` but writes that down only when it quits (seen on
    /// 2026-09-24: stopped at the password prompt after `logout`, it kept the revoked login, and
    /// the next sign-in was refused with it). So it quits, and a second run proves the login gone.
    @Test func `signing out logs out, quits so that steamcmd writes it down, then proves the login gone`() {
        let effects = Self.talk(.signOut(account: "someone"), runs: [
            [.console, .savedLogin, .signedIn, .console, .other, .console, .other],
            [.console, .noSavedLogin, .passwordPrompt],
        ])
        let expected: [Effect] = [
            .type("login someone"), .report(.signingOut),
            .type("logout"), .type("quit"), .restart,
            .type("login someone"),
            .finish(.success(.signedOut)), .stop,
        ]
        #expect(effects == expected)
    }

    /// Signed in with the saved login, logged out and quit: what the next run says, and how the sign-out ends.
    static let afterLogout: [Row<[SteamLine], [Effect]>] = [
        Row("the saved login gone: signed out", [.console, .noSavedLogin], [.finish(.success(.signedOut)), .stop]),
        Row("asked for the password: signed out", [.console, .passwordPrompt], [.finish(.success(.signedOut)), .stop]),
        Row(
            "the saved login still there: not signed out",
            [.console, .savedLogin, .signedIn, .console],
            [.finish(.failure(.stillSignedIn)), .type("quit")]
        ),
        Row(
            "Steam cannot be reached to try: not known to be signed out",
            [.console, .signInFailed("No Connection"), .console],
            [.finish(.failure(.noConnection)), .type("quit")]
        ),
        Row("back at the console with neither", [.console, .other, .console], [.finish(.failure(.noAnswer)), .type("quit")]),
    ]

    @Test(arguments: afterLogout)
    func `a sign-out succeeds only when the saved login is seen to be gone`(row: Row<[SteamLine], [Effect]>) {
        let signedIn: [SteamLine] = [.console, .savedLogin, .signedIn, .console, .console]
        let effects = Self.talk(.signOut(account: "someone"), runs: [signedIn, row.input])
        let loggedOut: [Effect] = [.type("login someone"), .report(.signingOut), .type("logout"), .type("quit"), .restart]
        let expected: [Effect] = loggedOut + [.type("login someone")] + row.expected
        #expect(effects == expected)
    }

    @Test func `steamcmd failing to go after logout is a failure`() {
        var conversation = SteamConversation(job: .signOut(account: "someone"))
        for line: SteamLine in [.console, .savedLogin, .signedIn, .console, .console] {
            _ = conversation.read(line)
        }
        #expect(conversation.exited(status: 6) == [.finish(.failure(.toolStopped(status: 6)))])
    }

    @Test func `signing out with a saved login Steam refuses logs out of it too`() {
        let effects = Self.talk(.signOut(account: "someone"), runs: [
            [.console, .savedLogin, .signInFailed("Access Denied"), .console, .console],
            [.console, .noSavedLogin],
        ])
        let expected: [Effect] = [
            .type("login someone"), .report(.signingOut), .type("logout"), .type("quit"), .restart,
            .type("login someone"), .finish(.success(.signedOut)), .stop,
        ]
        #expect(effects == expected)
    }

    @Test func `signing out with no saved login has nothing to take back`() {
        let effects = Self.talk(.signOut(account: "someone"), [.console, .noSavedLogin, .passwordPrompt])
        #expect(effects == [.type("login someone"), .report(.signingOut), .finish(.success(.signedOut)), .stop])
    }

    @Test func `signing out when Steam cannot be reached says so`() {
        let effects = Self.talk(.signOut(account: "someone"), [.console, .savedLogin, .signInFailed("No Connection"), .console])
        #expect(Array(effects.suffix(2)) == [.finish(.failure(.noConnection)), .type("quit")])
    }
}
