import Foundation
import LivepaperWorkshop
import os

/// What the Workshop runs on: Valve's steamcmd with the user's own login, or
/// the fakes run's stand-in, which touches neither Steam nor the network. Nothing else differs between the two.
nonisolated struct WorkshopServices: Sendable {
    typealias Progress = @Sendable (SteamProgress) -> Void
    typealias Code = @Sendable (SteamGuard, _ again: Bool) async -> SteamSecret?

    var isFakes: Bool
    /// The account steamcmd's saved login is under, kept between runs. Never a password.
    var loadAccount: @Sendable () -> String?
    var saveAccount: @Sendable (String?) -> Void
    /// steamcmd is in place.
    var isInstalled: @Sendable () -> Bool
    /// Fetches steamcmd from Valve, checks it, and lets it update itself.
    var install: @Sendable (_ progress: @escaping Progress) async throws -> Void
    /// Checks steamcmd can and may run (Valve's signature, Rosetta), then runs one job.
    var run: @Sendable (
        _ job: SteamJob, _ password: SteamSecret?, _ code: @escaping Code, _ progress: @escaping Progress
    ) async throws -> SteamOutcome
    /// What an item's page says about it, for a pasted link. Nil when it cannot be read.
    var page: @Sendable (WorkshopItemID) async -> WorkshopItemPage?
    /// A picture from the web, such as an item's preview, saved to a file of its own for the rows' posters.
    var picture: @Sendable (URL) async -> URL?
}

nonisolated extension WorkshopServices {
    /// steamcmd in Livepaper's folder in Application Support, working in Steam's
    /// own folder in the user's home, where it keeps its login and its downloads.
    static func wired() -> WorkshopServices {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let tool = SteamCmdTool(home: home)
        // Checked by `tool` before every start of steamcmd, the one after it updates itself included.
        let steamcmd = SteamCmd(tool: tool, home: home)
        return WorkshopServices(
            isFakes: false,
            loadAccount: { UserDefaults.standard.string(forKey: accountKey) },
            saveAccount: { UserDefaults.standard.set($0, forKey: accountKey) },
            isInstalled: { tool.isInstalled },
            install: { progress in
                try FileManager.default.createDirectory(at: tool.folder.deletingLastPathComponent(), withIntermediateDirectories: true)
                try await tool.install()
                _ = try await steamcmd.run(.update, progress: progress, line: WorkshopLog.steamcmd)
            },
            run: { job, password, code, progress in
                try await steamcmd.run(job, password: password, code: code, progress: progress, line: WorkshopLog.steamcmd)
            },
            page: { item in
                var request = URLRequest(url: WorkshopLink.page(of: item))
                request.timeoutInterval = 20
                guard let (data, response) = try? await URLSession.shared.data(for: request),
                      (response as? HTTPURLResponse)?.statusCode == 200,
                      let html = String(bytes: data, encoding: .utf8) else { return nil }
                return WorkshopItemPage(html: html)
            },
            picture: { url in
                guard url.scheme == "https", let (file, response) = try? await URLSession.shared.download(from: url),
                      (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
                let kept = FileManager.default.temporaryDirectory.appending(path: "Livepaper Workshop \(UUID().uuidString)")
                return (try? FileManager.default.moveItem(at: file, to: kept)).map { kept }
            }
        )
    }

    /// The defaults key for the account name.
    private static let accountKey = "WorkshopAccount"
}

nonisolated extension WorkshopServices {
    /// The fakes run's Workshop: an account in memory and steamcmd's steps on
    /// the clock. A password of "code" asks for a code (any will do), "approve"
    /// waits for the Steam Mobile app, "wrong" is refused. An item with an even
    /// number downloads as a made-up video item in a temporary folder, which the
    /// fakes' importer takes; an odd one is refused as an account without
    /// Wallpaper Engine would be.
    static func fakes() -> WorkshopServices {
        let account = OSAllocatedUnfairLock<String?>(initialState: nil)
        let installed = OSAllocatedUnfairLock(initialState: false)
        let step = Duration.milliseconds(600)
        return WorkshopServices(
            isFakes: true,
            loadAccount: { account.withLock { $0 } },
            saveAccount: { name in account.withLock { $0 = name } },
            isInstalled: { installed.withLock { $0 } },
            install: { progress in
                for percent in [0, 25, 60, 100] {
                    progress(.updating(percent: percent))
                    try await Task.sleep(for: step)
                }
                installed.withLock { $0 = true }
            },
            run: { job, password, code, progress in
                progress(.updating(percent: 0))
                try await Task.sleep(for: step)
                switch job {
                case .signIn:
                    progress(.signingIn)
                    try await Task.sleep(for: step)
                    return try await fakeSignIn(password: password, code: code, progress: progress, step: step)
                case .download(let item, _):
                    progress(.signingIn)
                    try await Task.sleep(for: step)
                    progress(.downloading)
                    try await Task.sleep(for: step * 3)
                    guard item.value.isMultiple(of: 2) else { throw WorkshopError.notOwned }
                    let folder = try writeFakeItem(item)
                    return .downloaded(folder: folder.path, bytes: 1)
                case .signOut:
                    progress(.signingOut)
                    try await Task.sleep(for: step)
                    return .signedOut
                case .update:
                    return .updated
                }
            },
            page: { item in
                WorkshopItemPage(app: wallpaperEngineApp, title: "Fake Item \(item)", type: "Video", preview: nil)
            },
            picture: { _ in nil }
        )
    }

    private static func fakeSignIn(
        password: SteamSecret?, code: Code, progress: Progress, step: Duration
    ) async throws -> SteamOutcome {
        switch password.map(FakePassword.init) {
        case .wrong?, nil:
            throw WorkshopError.wrongPassword
        case .code?:
            guard await code(.email, false) != nil else { throw CancellationError() }
        case .approve?:
            progress(.waitingForApproval)
            try await Task.sleep(for: step * 4)
        case .plain?:
            break
        }
        return .signedIn
    }

    /// A made-up Wallpaper Engine video item, as steamcmd would leave one.
    private static func writeFakeItem(_ item: WorkshopItemID) throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appending(path: "Livepaper Fakes/workshop/content/431960/\(item)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let project = #"{"type": "video", "file": "loop.mp4", "title": "Fake Item \#(item)"}"#
        try Data(project.utf8).write(to: folder.appending(path: "project.json"))
        try Data().write(to: folder.appending(path: "loop.mp4"))
        return folder
    }
}

/// What the fakes run's sign-in does, from the password typed.
private nonisolated enum FakePassword {
    case wrong, code, approve, plain

    init(_ secret: SteamSecret) {
        self = if secret.matches("wrong") {
            .wrong
        } else if secret.matches("code") {
            .code
        } else if secret.matches("approve") {
            .approve
        } else {
            .plain
        }
    }
}
