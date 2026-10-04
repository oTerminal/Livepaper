import AppKit
import DesignSystem
import Foundation
import LivepaperCore
import LivepaperImport
import UniformTypeIdentifiers

// Imports: a drop, the Import button and Command-O send every URL through
// `discoverSources`, the candidates wait in the `ImportList`, and one import
// runs at a time. The model is the importer's library, so an import's insert
// is saved like any other change.

extension AppModel {
    func wallpaper(withFingerprint fingerprint: Fingerprint) async throws -> Wallpaper? {
        library.wallpaper(withFingerprint: fingerprint)
    }

    func wallpaper(withID id: WallpaperID) async throws -> Wallpaper? {
        library[id]
    }

    /// Saved before it counts, then the displays follow; throws and does neither when it cannot be saved.
    func insert(_ wallpaper: Wallpaper) async throws {
        try change(library: library.inserting(wallpaper))
    }
}

extension AppModel {
    /// Files and folders, as dropped or chosen. A Wallpaper Engine folder gives
    /// its one video item; any other folder is searched. What is skipped, or
    /// cannot be read, says why in a toast; the rest join the import list.
    func importItems(at urls: [URL]) {
        guard canImport, !urls.isEmpty else { return }
        Task { _ = await enqueueImport(urls) }
    }

    /// `importItems(at:)`, for onboarding's first card, which waits on its
    /// rows (`ImportList.batch`): the rows its sources are on, and what never
    /// reached the list. A source the list already has waits on that row.
    func enqueueImport(_ urls: [URL]) async -> EnqueuedImport {
        let found = await Discovering.run(urls)
        guard canImport else { return EnqueuedImport() }
        for skipped in found.skipped {
            showToast(.skipped(skipped))
        }
        for failure in found.failures {
            showToast(.failed(name: failure.name, error: failure.error))
        }
        var enqueued = EnqueuedImport(
            notListed: found.skipped.map(NotImported.skipped) + found.failures.map { NotImported(name: $0.name, error: $0.error) }
        )
        guard !found.candidates.isEmpty else { return enqueued }
        let ids = found.candidates.map { _ in UUID() }
        perform(importList.enqueue(found.candidates, ids: ids))
        enqueued.rows = zip(ids, found.candidates).map { id, candidate in
            let source = candidate.source.standardizedFileURL.path
            let row = importList.rows.contains { $0.id == id } ? id
                : importList.rows.last { $0.candidate.source.standardizedFileURL.path == source }?.id ?? id
            return (row, candidate.name)
        }
        return enqueued
    }

    /// The Open panel, for the Import button and Command-O: files and folders,
    /// several at once. A sheet on the library window when that window is in
    /// front, since what is chosen goes into it; a panel of its own otherwise
    /// (Command-O from Settings).
    func chooseFilesToImport() {
        chooseFiles { [weak self] urls in self?.importItems(at: urls) }
    }

    /// The Open panel, handing what is chosen to `chosen`: onboarding's first
    /// card takes it too, as a sheet on its own window.
    func chooseFiles(_ chosen: @escaping ([URL]) -> Void) {
        guard canImport else { return }
        let panel = NSOpenPanel()
        panel.title = "Import"
        panel.prompt = "Import"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie, .gif, .folder] + importableExtensions.sorted().compactMap { UTType(filenameExtension: $0) }
        let answered: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK else { return }
            chosen(panel.urls)
        }
        if let window = NSApp.keyWindow, window.isLibraryWindow || window.isOnboardingWindow, window.attachedSheet == nil {
            panel.beginSheetModal(for: window, completionHandler: answered)
            let line = window.isLibraryWindow ? AppLog.choosingFiles(asSheet: true) : OnboardingLog.choosingFile
            AppLog.logger.notice("\(line, privacy: .public)")
        } else {
            NSApp.activate()
            panel.begin(completionHandler: answered)
            AppLog.logger.notice("\(AppLog.choosingFiles(asSheet: false), privacy: .public)")
        }
    }

    /// A row's cancel: a running import's stream is dropped, which stops it; a
    /// waiting row is taken away, and so is a failed one ("Remove from List").
    func cancelImport(_ row: ImportList.Row.ID) {
        perform(importList.cancel(row))
    }

    /// A failed row waits again where it is.
    func retryImport(_ row: ImportList.Row.ID) {
        perform(importList.retry(row))
    }

    /// A plain toast of the import's; a delete's undo toast it replaces is final.
    func showToast(_ toast: ImportToast) {
        toasts.send(.show(toast.toastItem))
    }

    // MARK: Running the list

    /// Carries out what the list answered. Which row runs, what a row shows and
    /// what a toast says are the list's; the model only runs and reports.
    private func perform(_ effects: [ImportList.Effect]) {
        for effect in effects {
            switch effect {
            case .start(let id, let candidate):
                importChecks.removeValue(forKey: id)?.cancel()
                start(id, candidate)
            case .check(let id, let candidate):
                check(id, candidate)
            case .cancel(let id):
                importChecks.removeValue(forKey: id)?.cancel()
                if runningImport?.id == id {
                    runningImport?.task.cancel()
                    runningImport = nil
                }
            case .toast(let toast):
                showToast(toast)
            }
        }
        scheduleImportTick()
    }

    /// Reads the import's stream until it ends. Cancelling the task drops the stream, and that cancels the import.
    private func start(_ id: UUID, _ candidate: ImportCandidate) {
        guard let importer else { return }
        let events = importer.events(importing: candidate)
        let task = Task { [weak self] in
            do {
                for try await event in events {
                    self?.received(event, for: id)
                }
            } catch {
                self?.failed(id, candidate, error)
            }
            if self?.runningImport?.id == id {
                self?.runningImport = nil
            }
        }
        runningImport = (id, task)
    }

    /// Looks for a waiting row's file in the library beside the running import.
    /// A file that cannot be read says so when its turn comes.
    private func check(_ id: UUID, _ candidate: ImportCandidate) {
        guard let importer else { return }
        importChecks[id] = Task { [weak self] in
            let existing = try? await importer.existingWallpaper(for: candidate)
            guard !Task.isCancelled, let self else { return }
            importChecks[id] = nil
            if let existing {
                AppLog.logger.notice("\(AppLog.importDuplicate(of: existing), privacy: .public)")
            }
            perform(importList.checked(id, existing: existing, at: Date()))
        }
    }

    /// The list ignores what arrives for a row that is no longer running; the log keeps it,
    /// since a cancel that came during the commit still imported the file.
    private func received(_ event: ImportEvent, for id: UUID) {
        if case .finished(let outcome) = event {
            switch outcome {
            case .imported(let wallpaper, _):
                AppLog.logger.notice("\(AppLog.importFinished(wallpaper), privacy: .public)")
            case .importedScene(let wallpaper, let preparation, let poster):
                AppLog.logger.notice("\(AppLog.importFinished(wallpaper), privacy: .public)")
                AppLog.log(preparation, of: wallpaper.id)
                AppLog.log(poster, of: wallpaper.id)
            case .duplicate(let wallpaper):
                AppLog.logger.notice("\(AppLog.importDuplicate(of: wallpaper), privacy: .public)")
            }
        }
        perform(importList.received(event, for: id, at: Date()))
    }

    private func failed(_ id: UUID, _ candidate: ImportCandidate, _ error: any Error) {
        if !(error is CancellationError) {
            AppLog.logger.error("\(AppLog.importFailed(candidate.name, error), privacy: .public)")
        }
        perform(importList.failed(id, error: error, at: Date()))
    }

    /// Finished rows, and failed rows Retry cannot help, leave `ImportList.finishedLifetime` after they ended.
    private func scheduleImportTick() {
        importTick?.cancel()
        importTick = nil
        guard let next = importList.nextTick else { return }
        importTick = Task { [weak self] in
            try? await Task.sleep(for: .seconds(max(next.timeIntervalSinceNow, 0)))
            guard !Task.isCancelled, let self else { return }
            perform(importList.tick(at: Date()))
        }
    }
}

extension AppModel {
    // MARK: Preparing scenes again

    /// At launch, after the sweep: scenes whose programs are missing (imported
    /// without the shader tools) or were translated by an older build get them
    /// now, one at a time, while the launch goes on. Until then the extension
    /// holds each one's poster. Then each scene whose poster is still the one
    /// cut from its preview has it drawn from the scene, and every picture of
    /// it on screen is read again. Not when the library could not be read,
    /// since nothing is written then.
    func prepareScenes() {
        let scenes = library.wallpapers.filter { $0.scene != nil }
        guard libraryProblem == nil, !scenes.isEmpty else { return }
        let services = services
        let art = art
        watches.append(Task {
            await services.prepareScenes(
                scenes,
                { @MainActor wallpaper, outcome in AppLog.log(outcome, of: wallpaper.id) },
                { @MainActor wallpaper, outcome in
                    AppLog.log(outcome, of: wallpaper.id)
                    if case .drawn = outcome { art.posterChanged(for: wallpaper) }
                }
            )
        })
    }
}

/// What an import that is waited on put on the list, and what never reached it: skipped, or not searched.
struct EnqueuedImport {
    /// The row each candidate is on, and the candidate's name.
    var rows: [(id: UUID, name: String)] = []
    var notListed: [NotImported] = []
}

/// Discovery reads the disk, so it runs off the main actor.
private nonisolated enum Discovering {
    struct Found: Sendable {
        var candidates: [ImportCandidate] = []
        var skipped: [SkippedSource] = []
        var failures: [Failure] = []
    }

    /// A URL that could not be searched, named as a candidate would be.
    struct Failure: Sendable {
        let name: String
        let error: any Error
    }

    @concurrent
    static func run(_ urls: [URL]) async -> Found {
        var found = Found()
        for url in urls {
            do {
                let discovery = try discoverSources(at: url)
                found.candidates += discovery.candidates
                found.skipped += discovery.skipped
            } catch {
                found.failures.append(Failure(name: url.deletingPathExtension().lastPathComponent, error: error))
            }
        }
        return found
    }
}
