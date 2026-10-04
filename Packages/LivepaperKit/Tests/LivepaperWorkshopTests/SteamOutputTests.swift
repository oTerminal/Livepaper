import Foundation
import Testing
import LivepaperWorkshop

/// steamcmd's own lines, read into what they mean.
///
/// The lines marked "seen" are what Valve's macOS steamcmd (client version
/// 1788292693) printed on 2026-09-23, driven over a pty from its `Steam>`
/// console: with the saved login of an account that owns Wallpaper Engine, with
/// an anonymous login, and with an account it had no login for. The account's
/// name, its Steam ID and the home folder are replaced; nothing else is changed.
/// The lines marked "log" are from steamcmd's `console_log.txt` of the same day,
/// which puts a time in front of each. The rest are Steam Guard's prompts and
/// Steam's results as Valve's steamcmd prints them, which a check on this Mac
/// could not bring about without the account owner's phone.
struct SteamOutputTests {
    static let lonelyCat = WorkshopItemID(3_289_988_463)!
    static let folder = "/Users/someone/Library/Application Support/Steam/steamapps/workshop/content/431960/3289988463"

    static let lines: [Row<String, SteamLine>] = [
        // Starting (seen)
        Row("seen: where it logs", "Redirecting stderr to '/Users/someone/Library/Application Support/Steam/logs/stderr.txt'", .other),
        Row("seen: after a stop it did not choose", "Looks like steam didn't shutdown cleanly, scheduling immediate update check", .other),
        Row("seen: looking for an update of itself", "[  0%] Checking for available updates...", .updating(percent: 0)),
        Row("seen: checking its files", "[----] Verifying installation...", .updating(percent: nil)),
        Row("its first run, fetching itself", "[ 45%] Downloading update (5,678 of 12,345 KB)...", .updating(percent: 45)),
        Row("its first run, done", "[100%] Download Complete.", .updating(percent: 100)),
        Row("seen: its banner", "Steam Console Client (c) Valve Corporation - version 1788292693", .other),
        Row("seen: ready", "Loading Steam API...OK", .other),
        Row("seen: the platform it is told to fetch for", "\"@sSteamCmdForcePlatformType\" = \"windows\"", .other),
        Row("seen: its console, waiting", "Steam>", .console),

        // Signing in (seen)
        Row("seen: a saved login", "Logging in using cached credentials.", .savedLogin),
        Row("seen: no saved login", "Cached credentials not found.", .noSavedLogin),
        Row("seen: asking for the password", "password: ", .passwordPrompt),
        Row("seen: signing in", "Logging in user 'someone' [U:1:0] to Steam Public...OK", .other),
        Row("seen: an anonymous login", "Connecting anonymously to Steam Public...OK", .other),
        Row("seen: the account's settings", "Waiting for client config...OK", .other),
        Row("seen: signed in", "Waiting for user info...OK", .signedIn),

        // Signing in (log)
        Row("log: a password Steam refused", "[2026-09-23 20:50:27] ERROR (Invalid Password)", .signInFailed("Invalid Password")),
        Row("log: Steam not answering", "[2026-09-23 20:52:18] ERROR (Timeout)", .signInFailed("Timeout")),
        Row("log: trying again by itself", "[2026-09-23 20:52:14] Retrying... ", .other),
        Row("log: signed in", "[2026-09-23 20:52:59] OK", .other),
        Row("log: the password prompt's own line", "password: ", .passwordPrompt),
        Row(
            "the refusal on the line that started the sign-in, as the console prints it",
            "Logging in user 'someone' [U:1:0] to Steam Public...ERROR (Invalid Password)",
            .signInFailed("Invalid Password")
        ),

        // Steam Guard, and Steam's other results
        Row("the code Steam sends by email", "Steam Guard code:", .codePrompt(.email)),
        Row("the code the Steam Mobile app shows", "Two-factor code:", .codePrompt(.authenticator)),
        Row(
            "the Steam Mobile app asked to approve",
            "Please confirm the login in the Steam Mobile app on your phone.",
            .other
        ),
        Row("waiting for that approval", "Waiting for confirmation...", .awaitingApproval),
        Row("the approval given", "Waiting for confirmation...OK", .other),
        Row("a wrong code from the app", "ERROR (Two-factor code mismatch)", .signInFailed("Two-factor code mismatch")),
        Row("a wrong code from the email", "ERROR (Invalid Login Auth Code)", .signInFailed("Invalid Login Auth Code")),
        Row("too many tries", "ERROR (Rate Limit Exceeded)", .signInFailed("Rate Limit Exceeded")),
        Row("no network", "ERROR (No Connection)", .signInFailed("No Connection")),
        Row("an older refusal", "FAILED login with result code Two-factor code mismatch", .signInFailed("Two-factor code mismatch")),
        Row("another older form", "Login Failure: Rate Limit Exceeded", .signInFailed("Rate Limit Exceeded")),

        // Downloading (seen)
        Row("seen: starting a download", "Downloading item 3289988463 ...", .downloading(lonelyCat)),
        Row(
            "seen: a warning on the same line as the start of a download",
            "Downloading item 3289988463 ...PosixFileOpen: RESOLVE_BENEATH unsupported, falling back to plain open()",
            .downloading(lonelyCat)
        ),
        Row(
            "a warning in front of the result",
            "PosixFileOpen: RESOLVE_BENEATH unsupported, falling back to plain open()Success. Downloaded item 1 to \"/a\" (2 bytes)",
            .downloaded(WorkshopItemID(1)!, folder: "/a", bytes: 2)
        ),
        Row(
            "seen: a download that worked, with the space steamcmd leaves at the end",
            "Success. Downloaded item 3289988463 to \"\(folder)\" (4404844 bytes) ",
            .downloaded(lonelyCat, folder: folder, bytes: 4_404_844)
        ),
        Row(
            "seen: an item Steam does not have",
            "ERROR! Download item 1 failed (File Not Found).",
            .downloadFailed(WorkshopItemID(1), "File Not Found")
        ),
        Row(
            "seen: an item the account may not download",
            "ERROR! Download item 3289988463 failed (Failure).",
            .downloadFailed(lonelyCat, "Failure")
        ),
        Row("an older steamcmd running out of time", "ERROR! Timeout downloading item 3289988463", .downloadFailed(lonelyCat, "Timeout")),
        Row("log: a warning while downloading", "PosixFileOpen: RESOLVE_BENEATH unsupported, falling back to plain open()", .other),

        // Leaving (seen)
        Row("seen: quitting", "Unloading Steam API...OK", .other),
        Row("nothing", "", .other),
    ]

    @Test(arguments: lines)
    func `reads a line of steamcmd's`(row: Row<String, SteamLine>) {
        #expect(readSteamLine(row.input) == row.expected)
    }

    @Test func `leaves out a terminal's colours and carriage returns`() {
        #expect(readSteamLine("\u{1B}[0mWaiting for user info...OK\r") == .signedIn)
        #expect(readSteamLine("\u{1B}[1;33mERROR (Timeout)\u{1B}[0m") == .signInFailed("Timeout"))
    }

    @Test func `a download's folder with a quote in it keeps it`() {
        let line = #"Success. Downloaded item 1 to "/Users/some "one"/1" (10 bytes)"#
        #expect(readSteamLine(line) == .downloaded(WorkshopItemID(1)!, folder: "/Users/some \"one\"/1", bytes: 10))
    }

    // MARK: The transcript

    /// What the console printed after `login`, a bad item and a good one, seen on 2026-09-23, byte for byte but for the account.
    static let savedLoginSession = """
    Redirecting stderr to '/Users/someone/Library/Application Support/Steam/logs/stderr.txt'\r
    [  0%] Checking for available updates...\r
    [----] Verifying installation...\r
    Steam Console Client (c) Valve Corporation - version 1788292693\r
    -- type 'quit' to exit --\r
    Loading Steam API...OK\r
    "@sSteamCmdForcePlatformType" = "windows"\r
    \r
    Steam>
    """

    @Test func `reads a prompt that has no line ending yet`() {
        var transcript = SteamTranscript()
        let read = transcript.read(Data(Self.savedLoginSession.utf8))
        #expect(read.filter { $0 != .other } == [.updating(percent: 0), .updating(percent: nil), .console])
    }

    @Test func `reads each prompt once, and what follows it on the same line afresh`() {
        var transcript = SteamTranscript()
        #expect(transcript.read(Data("Steam>".utf8)) == [.console])
        #expect(transcript.read(Data()) == [])
        // Echo is off, so the next line starts where the prompt was.
        #expect(transcript.read(Data("Logging in using cached credentials.\r\n".utf8)) == [.savedLogin])
        #expect(transcript.read(Data("Cached credentials not found.\r\n\r\npassword: ".utf8)) == [.noSavedLogin, .other, .passwordPrompt])
    }

    @Test func `reads a line split across reads`() {
        var transcript = SteamTranscript()
        #expect(transcript.read(Data("Waiting for user".utf8)) == [])
        #expect(transcript.read(Data(" info...".utf8)) == [])
        #expect(transcript.read(Data("OK\r\nSte".utf8)) == [.signedIn])
        #expect(transcript.read(Data("am>".utf8)) == [.console])
    }

    @Test func `says it is waiting for the Steam Mobile app while the line is still open`() {
        var transcript = SteamTranscript()
        #expect(transcript.read(Data("Waiting for confirmation...".utf8)) == [.awaitingApproval])
        #expect(transcript.read(Data("".utf8)) == [])
        #expect(transcript.read(Data("OK\r\n".utf8)) == [.other])
    }

    @Test func `a character split between two reads is read whole`() {
        var transcript = SteamTranscript()
        let line = Data("Success. Downloaded item 1 to \"/Users/Zoë/1\" (10 bytes)\r\n".utf8)
        let cut = line.firstIndex(of: 0xC3)! + 1
        #expect(transcript.read(line[..<cut]) == [])
        #expect(transcript.read(line[cut...]) == [.downloaded(WorkshopItemID(1)!, folder: "/Users/Zoë/1", bytes: 10)])
    }

    @Test func `keeps its last lines to say what went wrong, and no more than a few`() {
        var transcript = SteamTranscript()
        for number in 1...40 {
            _ = transcript.read(Data("line \(number)\r\n".utf8))
        }
        #expect(transcript.lastLines.count == SteamTranscript.linesKept)
        #expect(transcript.lastLines.last == "line 40")
    }
}
