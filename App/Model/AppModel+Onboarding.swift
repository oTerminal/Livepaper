import Foundation
import LivepaperCore
import LivepaperImport
import Observation

// Onboarding's part of the model: the first wallpaper, imported through
// the import list as any import is and set on every display, and leaving
// recorded, so that the next launch offers to make Livepaper the wallpaper again.

extension AppModel {
    /// How the first card's import ended.
    enum FirstWallpaperOutcome: Equatable {
        /// On every display now.
        case set(Wallpaper)
        /// Why nothing came of it, in a sentence.
        case failed(String)
    }

    /// Imports what was dropped on the first card, chosen, or picked from the
    /// samples, and sets the first wallpaper that comes of it on every display:
    /// a new one, or the one a file already is in the library. `progress` hears
    /// the import's stage as it runs. The rest of several files go on importing.
    func importFirstWallpaper(from urls: [URL], progress: @escaping (ImportBatch) -> Void) async -> FirstWallpaperOutcome {
        guard canImport else {
            return .failed(libraryProblem == nil ? "Livepaper is still starting. Try again in a moment." : Self.unwritable)
        }
        let enqueued = await enqueueImport(urls)
        guard canImport else { return .failed(Self.unwritable) }
        guard let first = enqueued.rows.first else { return .failed(Self.nothingToImport(enqueued.notListed)) }
        let rows = enqueued.rows.map(\.id)
        for await batch in Observations({ self.importList.batch(rows) }) {
            switch batch {
            case .importing:
                progress(batch)
            case .wallpaper(let wallpaper):
                setOnAllDisplays(.wallpaper(wallpaper.id))
                return .set(wallpaper)
            case .failed(let reason):
                // No reason: its rows were taken off the list.
                let source = reason.map { NotImported(name: first.name, reason: $0) } ?? .cancelled(name: first.name)
                return .failed(source.line)
            }
        }
        return .failed(NotImported.cancelled(name: first.name).line)
    }

    /// Leaving Livepaper as the wallpaper, recorded before the app quits: the
    /// next launch shows onboarding's last card alone.
    func recordLeaving() {
        let record = services.onboarding.record
        record.record = record.record.leaving()
    }

    private static let unwritable = "The library could not be read, so nothing can be imported."

    /// Nothing to import where the user pointed: why, in a sentence.
    private static func nothingToImport(_ notListed: [NotImported]) -> String {
        notListed.first?.line ?? "There is nothing there that Livepaper can import."
    }
}
