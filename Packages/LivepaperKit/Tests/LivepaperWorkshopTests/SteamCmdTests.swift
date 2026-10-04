import Foundation
import Testing
import LivepaperImport
import LivepaperWorkshop

/// steamcmd driven over its pty, on `Fixtures/fake-steamcmd`: a script that
/// speaks steamcmd's console and never touches the network or Workshop files.
struct SteamCmdTests {
    static let lonelyCat = WorkshopItemID(3_289_988_463)!

    // MARK: Downloading

    @Test func `downloads with the saved login, and discovery finds the item in the folder`() async throws {
        let steam = try FakeSteam()
        try steam.saveLogin(for: "someone")
        let heard = Heard()
        let outcome = try await steam.steamcmd().run(
            .download(Self.lonelyCat, account: "someone"), progress: heard.progress, line: heard.line
        )
        let folder = steam.home.appending(path: "Library/Application Support/Steam/steamapps/workshop/content/431960/3289988463").path
        #expect(outcome == .downloaded(folder: folder, bytes: 58))
        #expect(heard.progress == [.updating(percent: 0), .updating(percent: nil), .signingIn, .downloading])

        let discovery = try discoverSources(at: URL(filePath: folder, directoryHint: .isDirectory))
        #expect(discovery.candidates.map(\.name) == ["Fake Item 3289988463"])
        #expect(discovery.skipped.isEmpty)
    }

    @Test func `a download with no saved login stops at the password prompt and types nothing`() async throws {
        let steam = try FakeSteam()
        await #expect(throws: WorkshopError.signInNeeded) {
            try await steam.steamcmd(["FAKE_PASSWORD": "hunter2"]).run(.download(Self.lonelyCat, account: "someone"))
        }
        #expect(!steam.hasSavedLogin(for: "someone"))
    }

    @Test func `an item Steam does not have is said so`() async throws {
        let steam = try FakeSteam()
        try steam.saveLogin(for: "someone")
        await #expect(throws: WorkshopError.itemNotFound) {
            try await steam.steamcmd().run(.download(WorkshopItemID(1)!, account: "someone"))
        }
    }

    // MARK: Signing in

    @Test func `signs in with a password typed at its prompt, never passed as an argument or echoed`() async throws {
        let steam = try FakeSteam()
        let heard = Heard()
        let outcome = try await steam.steamcmd(["FAKE_PASSWORD": "hunter2 with spaces"]).run(
            .signIn(account: "someone"), password: .of("hunter2 with spaces"), progress: heard.progress, line: heard.line
        )
        #expect(outcome == .signedIn)
        #expect(steam.hasSavedLogin(for: "someone"))
        #expect(steam.arguments == "+@sSteamCmdForcePlatformType\nwindows\n")
        #expect(!heard.lines.isEmpty)
        #expect(!heard.lines.contains { $0.contains("hunter2") || $0.contains("login someone") })
    }

    @Test func `a wrong password is said so`() async throws {
        let steam = try FakeSteam()
        await #expect(throws: WorkshopError.wrongPassword) {
            try await steam.steamcmd(["FAKE_PASSWORD": "hunter2"]).run(.signIn(account: "someone"), password: .of("hunter3"))
        }
        #expect(!steam.hasSavedLogin(for: "someone"))
    }

    @Test func `asks for the emailed code and types it`() async throws {
        let steam = try FakeSteam()
        let heard = Heard()
        let outcome = try await steam.steamcmd(["FAKE_PASSWORD": "hunter2", "FAKE_GUARD": "email", "FAKE_CODE": "F7K2Q"]).run(
            .signIn(account: "someone"), password: .of("hunter2"),
            code: { kind, again in
                heard.asked(kind, again: again)
                return .of("F7K2Q")
            }
        )
        #expect(outcome == .signedIn)
        #expect(heard.codes == ["email"])
    }

    @Test func `a wrong code from the app is said so`() async throws {
        let steam = try FakeSteam()
        await #expect(throws: WorkshopError.wrongCode) {
            try await steam.steamcmd(["FAKE_PASSWORD": "hunter2", "FAKE_GUARD": "app", "FAKE_CODE": "F7K2Q"]).run(
                .signIn(account: "someone"), password: .of("hunter2"), code: { _, _ in .of("AAAAA") }
            )
        }
    }

    @Test func `waits for the Steam Mobile app's approval, and says so`() async throws {
        let steam = try FakeSteam()
        let heard = Heard()
        let outcome = try await steam.steamcmd(["FAKE_PASSWORD": "hunter2", "FAKE_GUARD": "approve"]).run(
            .signIn(account: "someone"), password: .of("hunter2"), progress: heard.progress
        )
        #expect(outcome == .signedIn)
        #expect(heard.progress.contains(.waitingForApproval))
    }

    @Test func `a code the user does not give cancels the sign-in`() async throws {
        let steam = try FakeSteam()
        await #expect(throws: CancellationError.self) {
            try await steam.steamcmd(["FAKE_PASSWORD": "hunter2", "FAKE_GUARD": "email", "FAKE_CODE": "F7K2Q"]).run(
                .signIn(account: "someone"), password: .of("hunter2"), code: { _, _ in nil }
            )
        }
        #expect(!steam.hasSavedLogin(for: "someone"))
    }

    // MARK: Signing out, setting up, and going wrong

    @Test func `signing out takes the saved login back`() async throws {
        let steam = try FakeSteam()
        try steam.saveLogin(for: "someone")
        let outcome = try await steam.steamcmd().run(.signOut(account: "someone"))
        #expect(outcome == .signedOut)
        #expect(!steam.hasSavedLogin(for: "someone"))
    }

    @Test func `after signing out, signing in again asks for the password`() async throws {
        let steam = try FakeSteam()
        try steam.saveLogin(for: "someone")
        _ = try await steam.steamcmd().run(.signOut(account: "someone"))
        let heard = Heard()
        let outcome = try await steam.steamcmd(["FAKE_PASSWORD": "hunter2"]).run(
            .signIn(account: "someone"), password: .of("hunter2"), line: heard.line
        )
        #expect(outcome == .signedIn)
        #expect(heard.lines.contains("Cached credentials not found."))
    }

    @Test func `a saved login Steam refuses is forgotten, and the sign-in asks for the password`() async throws {
        let steam = try FakeSteam()
        try steam.saveLogin(for: "someone", revoked: true)
        let heard = Heard()
        let outcome = try await steam.steamcmd(["FAKE_PASSWORD": "hunter2"]).run(
            .signIn(account: "someone"), password: .of("hunter2"), line: heard.line
        )
        #expect(outcome == .signedIn)
        #expect(steam.starts == 2)
        #expect(heard.lines.contains("Cached credentials not found."))
    }

    @Test func `a sign-in that meets a refused saved login twice gives up`() async throws {
        let steam = try FakeSteam()
        try steam.saveLogin(for: "someone", revoked: true)
        await #expect(throws: WorkshopError.steamSaid("Access Denied")) {
            try await steam.steamcmd(["FAKE_PASSWORD": "hunter2", "FAKE_KEEP_LOGIN": "1"]).run(
                .signIn(account: "someone"), password: .of("hunter2")
            )
        }
        #expect(steam.starts == 2)
    }

    @Test func `a download whose saved login Steam refuses asks to sign in`() async throws {
        let steam = try FakeSteam()
        try steam.saveLogin(for: "someone", revoked: true)
        await #expect(throws: WorkshopError.signInNeeded) {
            try await steam.steamcmd().run(.download(Self.lonelyCat, account: "someone"))
        }
    }

    @Test func `signing out with a saved login Steam refuses takes it back`() async throws {
        let steam = try FakeSteam()
        try steam.saveLogin(for: "someone", revoked: true)
        let outcome = try await steam.steamcmd().run(.signOut(account: "someone"))
        #expect(outcome == .signedOut)
        #expect(!steam.hasSavedLogin(for: "someone"))
    }

    @Test func `a logout that keeps the saved login is not a sign-out`() async throws {
        let steam = try FakeSteam()
        try steam.saveLogin(for: "someone")
        await #expect(throws: WorkshopError.stillSignedIn) {
            try await steam.steamcmd(["FAKE_KEEP_LOGIN": "1"]).run(.signOut(account: "someone"))
        }
        #expect(steam.hasSavedLogin(for: "someone"))
    }

    @Test func `the first run updates itself, restarts, then does the job`() async throws {
        let steam = try FakeSteam()
        let heard = Heard()
        let outcome = try await steam.steamcmd(["FAKE_UPDATE": "1"]).run(.update, progress: heard.progress)
        #expect(outcome == .updated)
        #expect(Array(heard.progress.prefix(3)) == [.updating(percent: 0), .updating(percent: 50), .updating(percent: 100)])
    }

    @Test func `steamcmd is checked before every start, the one after it updated itself included`() async throws {
        let steam = try FakeSteam()
        let checks = Tally()
        let outcome = try await steam.steamcmd(["FAKE_UPDATE": "1"], check: { checks.add() }).run(.update)
        #expect(outcome == .updated)
        #expect(steam.starts == 2)
        #expect(checks.value == 2)
    }

    @Test func `a steamcmd that fails the check after updating itself is not started again`() async throws {
        let steam = try FakeSteam()
        let checks = Tally()
        await #expect(throws: WorkshopError.toolUntrusted) {
            try await steam.steamcmd(["FAKE_UPDATE": "1"], check: { () throws(WorkshopError) in
                if checks.add() > 1 { throw .toolUntrusted }
            }).run(.update)
        }
        #expect(steam.starts == 1)
    }

    @Test func `a steamcmd that fails the check is never started`() async throws {
        let steam = try FakeSteam()
        await #expect(throws: WorkshopError.toolUntrusted) {
            try await steam.steamcmd(check: { () throws(WorkshopError) in throw .toolUntrusted }).run(.update)
        }
        #expect(steam.starts == 0)
    }

    @Test func `steamcmd dying on its own is a failure`() async throws {
        let steam = try FakeSteam()
        try steam.saveLogin(for: "someone")
        await #expect(throws: WorkshopError.toolStopped(status: 3)) {
            try await steam.steamcmd(["FAKE_CRASH": "1"]).run(.download(Self.lonelyCat, account: "someone"))
        }
    }

    @Test func `steamcmd saying nothing runs out of time`() async throws {
        let steam = try FakeSteam()
        await #expect(throws: WorkshopError.timedOut) {
            try await steam.steamcmd(["FAKE_SILENT": "1"], limits: SteamCmd.Limits(other: .milliseconds(500))).run(.update)
        }
    }

    @Test func `cancelling stops steamcmd, and what it started, at once`() async throws {
        let steam = try FakeSteam()
        let running = Task {
            try await steam.steamcmd(["FAKE_SILENT": "1"]).run(.update)
        }
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(10)
        while steam.sleeper == nil, clock.now < deadline {
            try await Task.sleep(for: .milliseconds(50))
        }
        let sleeper = try #require(steam.sleeper)

        let cancelled = clock.now
        running.cancel()
        await #expect(throws: CancellationError.self) { try await running.value }
        // Left alone, the fake would have gone by itself after 30 s.
        #expect(clock.now - cancelled < .seconds(5))
        // The program it started is gone too: a zombie for a moment, until launchd reaps it.
        while Darwin.kill(sleeper, 0) == 0, clock.now - cancelled < .seconds(5) {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(Darwin.kill(sleeper, 0) == -1 && errno == ESRCH)
    }

    @Test func `a program the system will not start is said so`() async throws {
        let folder = try TemporaryFolder()
        let executable = folder.file("steamcmd")
        FileManager.default.createFile(atPath: executable.path, contents: Data("not a program".utf8))
        await #expect(throws: WorkshopError.toolNotStarted) {
            try await SteamCmd(executable: executable, home: folder.url, check: {}).run(.update)
        }
    }

    @Test func `a secret with a line break in it is refused, and prints as dots`() {
        #expect(SteamSecret("hunter2\nlogout") == nil)
        #expect(SteamSecret("") == nil)
        #expect(SteamSecret("hunter2").map { "\($0)" } == "••••")
        #expect(SteamSecret("hunter2").map { String(reflecting: $0) } == "••••")
        #expect(SteamSecret("hunter2")?.matches("hunter2") == true)
        #expect(SteamSecret("hunter2")?.matches("hunter3") == false)
    }
}
