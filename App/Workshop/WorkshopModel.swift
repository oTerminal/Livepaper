import DesignSystem
import Foundation
import LivepaperImport
import LivepaperWorkshop
import Observation

/// Where the sign-in sheet shows: on the window the user asked from.
enum SignInHost: Equatable {
    case workshop
    case settings
}

/// The Workshop's model: the Steam account steamcmd's saved login
/// is under, the items being got, and the sign-in sheet while it is up. Every
/// decision is `LivepaperWorkshop`'s (`WorkshopDownloads`, `SteamConversation`,
/// the words); the model runs steamcmd, one job at a time, and hands each
/// downloaded folder to the import, which takes it from there.
///
/// The password and a Steam Guard code live in the sheet's fields and in the
/// one sign-in's task, as `SteamSecret`s, and nowhere else. Only the account
/// name is kept, because steamcmd's saved login is found by it.
@MainActor @Observable
final class WorkshopModel {
    /// The account steamcmd has a saved login for; nil until the user has signed in.
    private(set) var account: String?
    private(set) var downloads = WorkshopDownloads()
    /// The sign-in sheet's step while it is up.
    private(set) var signIn: SteamSignInStep?
    private(set) var signInHost: SignInHost?
    private(set) var isSigningOut = false
    /// Why the last sign-out did not work, until the next try.
    private(set) var signOutProblem: String?
    /// Items handed to the import this session: the Get button says done.
    private(set) var handedOver: Set<WorkshopItemID> = []
    /// Each row's preview, fetched from its page, as a temporary file: deleted
    /// when its row goes, and at Quit.
    private(set) var previews: [WorkshopItemID: URL] = [:]

    @ObservationIgnored let services: WorkshopServices
    /// Where a downloaded folder goes: the import, as a drop of it would.
    @ObservationIgnored private let library: AppModel
    /// Brings the Workshop window forward, to show a sign-in a download asked for.
    @ObservationIgnored var showWorkshop: () -> Void = {}
    @ObservationIgnored private var running: RunningDownload?
    @ObservationIgnored private var signingIn: Task<Void, Never>?
    @ObservationIgnored private var signingOut: Task<Void, Never>?
    @ObservationIgnored private var codeAnswer: CheckedContinuation<SteamSecret?, Never>?
    /// steamcmd runs one job at a time: two would both write Steam's folder.
    @ObservationIgnored private var isSteamBusy = false
    @ObservationIgnored private var steamWaiters: [CheckedContinuation<Void, Never>] = []

    init(services: WorkshopServices, library: AppModel) {
        self.services = services
        self.library = library
        account = services.loadAccount()
    }

    // MARK: Getting items

    /// Gets an item, with what its page says: its title, and a refusal the import would make anyway.
    func get(_ item: WorkshopItemID, page: WorkshopItemPage?) {
        WorkshopLog.logger.notice("\(WorkshopLog.getting(item), privacy: .public)")
        if let preview = page?.preview, previews[item] == nil {
            Task {
                guard let file = await services.picture(preview) else { return }
                // Its row may have gone, or another fetch of it come first, while this one was on its way.
                if previews[item] == nil, downloads.rows.contains(where: { $0.item == item }) {
                    previews[item] = file
                } else {
                    try? FileManager.default.removeItem(at: file)
                }
            }
        }
        perform(downloads.get(item, title: page?.title, refusal: page?.refusal))
    }

    /// Text pasted or dropped into the library: a Workshop link, or an item's
    /// number. Its page is read first, for its title and what it is. Answers
    /// whether the text named an item.
    @discardableResult
    func get(pasted text: String) -> Bool {
        guard let item = WorkshopLink.item(inPasted: text) else { return false }
        Task {
            let page = await services.page(item)
            get(item, page: page)
        }
        return true
    }

    func cancel(_ item: WorkshopItemID) {
        perform(downloads.cancel(item))
    }

    func retry(_ item: WorkshopItemID) {
        perform(downloads.retry(item))
    }

    /// The Get button's state for the item a page is of.
    func getState(for item: WorkshopItemID?, page: WorkshopItemPage?) -> WorkshopGetState {
        guard let item else { return .unavailable(reason: "Go to an item’s page to get it") }
        if let refusal = page?.refusal { return .unavailable(reason: refusal.words + ".") }
        if let row = downloads.rows.first(where: { $0.item == item }) {
            if case .failed = row.state { return .idle }
            return .working
        }
        return handedOver.contains(item) ? .done : .idle
    }

    // MARK: Signing in and out

    /// Puts the sign-in sheet up on `host`, at the account name and password.
    func beginSignIn(on host: SignInHost) {
        guard signIn == nil else { return }
        signInHost = host
        signIn = .credentials(problem: nil)
    }

    /// Signs in with what the sheet's fields hold. The password goes into this
    /// one sign-in's task and nowhere else.
    func submitSignIn(account name: String, password: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSteamAccountName(name) else {
            signIn = .credentials(problem: sentence(workshopFailureWords(.notAnAccountName).reason))
            return
        }
        guard let secret = SteamSecret(password) else {
            signIn = .credentials(problem: "A password cannot have a line break in it.")
            return
        }
        signIn = .working(detail: "Signing in to Steam", fraction: nil)
        WorkshopLog.logger.notice("\(WorkshopLog.signingIn, privacy: .public)")
        signingIn = Task {
            await takeSteam()
            defer { releaseSteam() }
            do {
                try await setUpIfNeeded { step in self.signInProgress(step) }
                _ = try await services.run(
                    .signIn(account: name),
                    secret,
                    { kind, again in await self.askForCode(kind, again: again) },
                    { step in Task { @MainActor in self.signInProgress(step) } }
                )
                try Task.checkCancellation()
                signedIn(as: name)
            } catch is CancellationError {
                WorkshopLog.logger.notice("\(WorkshopLog.signInCancelled, privacy: .public)")
            } catch {
                WorkshopLog.logger.error("\(WorkshopLog.signInFailed(error), privacy: .public)")
                guard signIn != nil else { return }
                signIn = .credentials(problem: problemWords(error))
            }
        }
    }

    /// The code the sheet's field holds, for the prompt steamcmd is waiting at.
    func submitCode(_ text: String) {
        guard let code = SteamSecret(text.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        signIn = .working(detail: "Signing in to Steam", fraction: nil)
        codeAnswer?.resume(returning: code)
        codeAnswer = nil
    }

    /// Cancel, Escape, or the sheet's window closing: steamcmd is stopped, and nothing is kept.
    func cancelSignIn() {
        codeAnswer?.resume(returning: nil)
        codeAnswer = nil
        signingIn?.cancel()
        signingIn = nil
        signIn = nil
        signInHost = nil
    }

    /// steamcmd's `logout`: the saved login is revoked, and Livepaper forgets the account.
    func signOut() {
        guard let account, !isSigningOut else { return }
        isSigningOut = true
        signOutProblem = nil
        signingOut = Task {
            await takeSteam()
            defer { releaseSteam() }
            do {
                try Task.checkCancellation()
                // With no steamcmd there is no saved login to take back.
                if services.isInstalled() {
                    _ = try await services.run(.signOut(account: account), nil, { _, _ in nil }, { _ in })
                }
                self.account = nil
                services.saveAccount(nil)
                WorkshopLog.logger.notice("\(WorkshopLog.signedOut, privacy: .public)")
            } catch is CancellationError {
                // Stopped by Quit: the account is kept, as steamcmd's saved login may be.
            } catch {
                signOutProblem = problemWords(error)
                WorkshopLog.logger.error("\(WorkshopLog.signOutFailed(error), privacy: .public)")
            }
            isSigningOut = false
            signingOut = nil
        }
    }

    /// Stops whatever steamcmd is doing, or waits to do, for Quit: it runs in a
    /// session of its own and would outlive the app. The previews go too.
    func stopAll() {
        cancelSignIn()
        signingOut?.cancel()
        running?.task.cancel()
        for file in previews.values {
            try? FileManager.default.removeItem(at: file)
        }
        previews = [:]
    }

    // MARK: Running the list

    private func perform(_ effects: [WorkshopDownloads.Effect]) {
        forgetPreviewsOfGoneRows()
        for effect in effects {
            switch effect {
            case .start(let item):
                start(item)
            case .cancel(let item):
                if running?.item == item {
                    running?.task.cancel()
                    running = nil
                }
            case .discover(let item, let folder):
                discover(item, in: folder)
            case .importFolder(let folder):
                library.importItems(at: [folder])
            case .askToSignIn:
                showWorkshop()
                beginSignIn(on: .workshop)
            }
        }
    }

    private func start(_ item: WorkshopItemID) {
        guard let account else {
            perform(downloads.failed(item, .signInNeeded))
            return
        }
        let id = UUID()
        let task = Task {
            await takeSteam()
            defer { releaseSteam() }
            guard !Task.isCancelled else { return }
            do {
                try await setUpIfNeeded { step in self.downloads.progress(item, step) }
                let outcome = try await services.run(
                    .download(item, account: account), nil, { _, _ in nil },
                    { step in Task { @MainActor in self.downloads.progress(item, step) } }
                )
                try Task.checkCancellation()
                guard case .downloaded(let folder, let bytes) = outcome else { throw WorkshopError.noAnswer }
                WorkshopLog.logger.notice("\(WorkshopLog.downloaded(item, bytes: bytes), privacy: .public)")
                perform(downloads.downloaded(item, folder: URL(filePath: folder, directoryHint: .isDirectory)))
            } catch is CancellationError {
                // Taken off the list by its cancel.
            } catch {
                WorkshopLog.logger.error("\(WorkshopLog.notGot(item, error), privacy: .public)")
                perform(downloads.failed(item, error as? WorkshopError ?? .noAnswer))
            }
            // Only this task's own handle: a Get of the same item after a cancel has one of its own.
            if running?.id == id { running = nil }
        }
        running = RunningDownload(id: id, item: item, task: task)
    }

    /// Reads the downloaded folder as a drop of it would be read; discovery reads the disk, so off the main actor.
    private func discover(_ item: WorkshopItemID, in folder: URL) {
        Task {
            let found = await Self.discovered(in: folder)
            let effects = downloads.discovered(item, found)
            if effects.contains(.importFolder(folder)) {
                handedOver.insert(item)
                WorkshopLog.logger.notice("\(WorkshopLog.handedOver(item), privacy: .public)")
            } else if let row = downloads.rows.first(where: { $0.item == item }), case .failed(let problem) = row.state {
                WorkshopLog.logger.notice("\(WorkshopLog.refused(item, problem), privacy: .public)")
            }
            perform(effects)
        }
    }

    @concurrent
    private nonisolated static func discovered(in folder: URL) async -> DiscoveredItem {
        (try? discoverSources(at: folder)).map(DiscoveredItem.init) ?? .nothing
    }

    /// A row's preview is shown nowhere once the row has gone: its item was
    /// handed to the import, which shows its own, or taken off the list.
    private func forgetPreviewsOfGoneRows() {
        let shown = Set(downloads.rows.map(\.item))
        for (item, file) in previews where !shown.contains(item) {
            try? FileManager.default.removeItem(at: file)
            previews[item] = nil
        }
    }

    // MARK: Sign-in steps

    private func signedIn(as name: String) {
        account = name
        services.saveAccount(name)
        signIn = nil
        signInHost = nil
        signingIn = nil
        WorkshopLog.logger.notice("\(WorkshopLog.signedIn, privacy: .public)")
        perform(downloads.signedIn())
    }

    private func signInProgress(_ step: SteamProgress) {
        guard signIn != nil else { return }
        switch step {
        case .updating(let percent?) where percent > 0:
            signIn = .working(detail: "Updating Steam’s download tool", fraction: Double(percent) / 100)
        case .updating:
            if case .working(_, _?) = signIn { return }
            signIn = .working(detail: "Starting Steam’s download tool", fraction: nil)
        case .signingIn, .downloading, .signingOut:
            signIn = .working(detail: "Signing in to Steam", fraction: nil)
        case .waitingForApproval:
            signIn = .approval
        }
    }

    private func askForCode(_ kind: SteamGuard, again: Bool) async -> SteamSecret? {
        guard signIn != nil else { return nil }
        signIn = .code(kind == .email ? .email : .app, problem: again ? sentence(workshopFailureWords(.wrongCode).reason) : nil)
        return await withCheckedContinuation { continuation in
            codeAnswer = continuation
        }
    }
}

/// The download running, told from a later one of the same item by its own `id`.
private struct RunningDownload {
    let id: UUID
    let item: WorkshopItemID
    let task: Task<Void, Never>
}

// Here, beside the class, since only this file may set what the class keeps.
extension WorkshopModel {
    // MARK: steamcmd

    /// Fetches steamcmd from Valve the first time it is needed.
    private func setUpIfNeeded(_ progress: @escaping @MainActor (SteamProgress) -> Void) async throws {
        guard !services.isInstalled() else { return }
        WorkshopLog.logger.notice("\(WorkshopLog.settingUp(), privacy: .public)")
        progress(.updating(percent: nil))
        try await services.install { step in Task { @MainActor in progress(step) } }
        WorkshopLog.logger.notice("\(WorkshopLog.setUp, privacy: .public)")
    }

    private func takeSteam() async {
        if isSteamBusy {
            await withCheckedContinuation { steamWaiters.append($0) }
        }
        isSteamBusy = true
    }

    private func releaseSteam() {
        if steamWaiters.isEmpty {
            isSteamBusy = false
        } else {
            steamWaiters.removeFirst().resume()
        }
    }

    // MARK: Words

    private func problemWords(_ error: any Error) -> String {
        sentence((error as? WorkshopError).map { workshopFailureWords($0).reason } ?? "Steam’s download tool could not do it")
    }

    private func sentence(_ reason: String) -> String {
        reason + "."
    }
}

extension WorkshopModel {
    /// A fakes model for the `#Preview`s, signed in to `account` or not.
    static func preview(library: AppModel = .preview(), account: String? = nil) -> WorkshopModel {
        let services = WorkshopServices.fakes()
        services.saveAccount(account)
        return WorkshopModel(services: services, library: library)
    }
}
