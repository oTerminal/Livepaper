import Foundation
import LivepaperWorkshop
import Synchronization

/// A folder of the test's own under the temporary directory, removed when the test lets go of it.
final class TemporaryFolder: Sendable {
    let url: URL

    init() throws {
        // The real path, so that paths compare equal to what the file system reports (/var is a link to /private/var).
        let temporary = FileManager.default.temporaryDirectory.path
        let real = realpath(temporary, nil).map { pointer in
            defer { free(pointer) }
            return String(cString: pointer)
        }
        url = URL(filePath: real ?? temporary, directoryHint: .isDirectory)
            .appending(path: "LivepaperWorkshopTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func file(_ path: String) -> URL {
        url.appending(path: path, directoryHint: .notDirectory)
    }

    func folder(_ path: String) -> URL {
        url.appending(path: path, directoryHint: .isDirectory)
    }
}

/// `Fixtures/fake-steamcmd` installed in a folder of its own, with a home of its own for its saved login and downloads.
struct FakeSteam {
    let folder: TemporaryFolder
    var home: URL { folder.folder("home") }
    var executable: URL { folder.file("steamcmd/steamcmd") }

    init() throws {
        folder = try TemporaryFolder()
        guard let fixture = Bundle.module.url(forResource: "Fixtures/fake-steamcmd", withExtension: nil) else {
            throw CocoaError(.fileNoSuchFile)
        }
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: fixture, to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    }

    /// steamcmd on the fake, with its behaviour set by `settings` (the script's FAKE_ variables).
    /// The fake carries no signature, so the check before each start is the test's own.
    func steamcmd(
        _ settings: [String: String] = [:], limits: SteamCmd.Limits = SteamCmd.Limits(),
        check: @escaping @Sendable () throws(WorkshopError) -> Void = {}
    ) -> SteamCmd {
        SteamCmd(executable: executable, home: home, check: check, extra: settings, limits: limits)
    }

    /// The program a silent fake waits on, once it has started it.
    var sleeper: pid_t? {
        (try? String(contentsOf: home.appending(path: "fake-steam/sleeper"), encoding: .utf8))
            .flatMap { pid_t($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    /// How many times the fake was started.
    var starts: Int {
        ((try? String(contentsOf: home.appending(path: "fake-steam/starts"), encoding: .utf8)) ?? "").split(separator: "\n").count
    }

    /// A saved login for the account, as a sign-in would have left it; `revoked`, one Steam refuses.
    func saveLogin(for account: String, revoked: Bool = false) throws {
        try FileManager.default.createDirectory(at: home.appending(path: "fake-steam"), withIntermediateDirectories: true)
        let contents = Data((revoked ? "revoked" : "").utf8)
        FileManager.default.createFile(atPath: home.appending(path: "fake-steam/login-\(account)").path, contents: contents)
    }

    func hasSavedLogin(for account: String) -> Bool {
        FileManager.default.fileExists(atPath: home.appending(path: "fake-steam/login-\(account)").path)
    }

    /// The arguments the fake was last started with, one per line.
    var arguments: String {
        (try? String(contentsOf: home.appending(path: "fake-steam/arguments"), encoding: .utf8)) ?? ""
    }
}

/// A number that callbacks on any thread add to.
final class Tally: Sendable {
    private let count = Mutex(0)

    var value: Int { count.withLock { $0 } }

    /// Adds one, and answers the new count.
    @discardableResult
    func add() -> Int {
        count.withLock { count in
            count += 1
            return count
        }
    }
}

/// What a run reported, gathered from its callbacks.
final class Heard: Sendable {
    private let state = Mutex((progress: [SteamProgress](), lines: [String](), codes: [String]()))

    var progress: [SteamProgress] { state.withLock { $0.progress } }
    var lines: [String] { state.withLock { $0.lines } }
    /// The code prompts asked, as "email" or "authenticator", with "again" when asked again.
    var codes: [String] { state.withLock { $0.codes } }

    func progress(_ step: SteamProgress) {
        state.withLock { $0.progress.append(step) }
    }

    func line(_ line: String) {
        state.withLock { $0.lines.append(line) }
    }

    func asked(_ kind: SteamGuard, again: Bool) {
        state.withLock { $0.codes.append("\(kind)\(again ? " again" : "")") }
    }
}

extension SteamSecret {
    static func of(_ text: String) -> SteamSecret {
        SteamSecret(text)!
    }
}
