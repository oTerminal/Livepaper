import Foundation
import LivepaperCore

/// Where imports started together have got to, for a caller that waits on them
/// rather than on the list as a whole: onboarding's first wallpaper.
public enum ImportBatch: Equatable, Sendable {
    /// None has given a wallpaper yet, and one is running or waiting: the name
    /// of the one that runs, else of the first that waits, and the running one's
    /// stage in words, nil while it waits.
    case importing(name: String, words: String?)
    /// The first of the rows, in the batch's order, to give a wallpaper: a new
    /// one, or the one its file already is in the library.
    case wallpaper(Wallpaper)
    /// None gave a wallpaper, and none is left to: the first failure's reason,
    /// nil when the rows were taken off the list without one.
    case failed(reason: String?)
}

extension ImportList {
    /// The batch on rows `ids`, in their order. Rows outside it are no part of it.
    public func batch(_ ids: [UUID]) -> ImportBatch {
        let batch = ids.compactMap { id in rows.first { $0.id == id } }
        if let wallpaper = batch.lazy.compactMap(\.state.wallpaper).first {
            return .wallpaper(wallpaper)
        }
        for row in batch {
            if case .running(_, let words, _) = row.state { return .importing(name: row.candidate.name, words: words) }
        }
        if let waiting = batch.first(where: { $0.state == .waiting }) {
            return .importing(name: waiting.candidate.name, words: nil)
        }
        let reason = batch.lazy.compactMap { row -> String? in
            if case .failed(let reason, _, _) = row.state { return reason }
            return nil
        }.first
        return .failed(reason: reason)
    }
}
