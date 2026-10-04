import Foundation
import LivepaperCore

/// The imports under the library's grid, one row per candidate. The app feeds
/// it what happens and carries out the effects it answers: one import runs at
/// a time, the rest wait their turn, and a file dropped again is said at once.
public struct ImportList: Equatable, Sendable {
    /// How long a finished row stays to be seen: a toast's lifetime.
    public static let finishedLifetime: Duration = .seconds(5)

    public struct Row: Identifiable, Equatable, Sendable {
        public let id: UUID
        /// The name and, for a Wallpaper Engine item, the preview the row shows.
        public let candidate: ImportCandidate
        public var state: RowState
    }

    public enum RowState: Equatable, Sendable {
        case waiting
        /// The stage in words and how far through it the import is, nil when the stage cannot tell.
        case running(stage: ImportStage, words: String, fraction: Double?)
        case finished(Wallpaper, at: Date)
        /// Nothing was imported: it is already in the library as this wallpaper.
        case duplicate(of: Wallpaper, at: Date)
        /// Why, in words, whether Retry can help, and when it failed.
        case failed(reason: String, canRetry: Bool, at: Date)
    }

    public enum Effect: Equatable, Sendable {
        /// Start this row's import.
        case start(UUID, ImportCandidate)
        /// Look for this row's source file in the library now, beside the running
        /// import rather than after it; `checked(_:existing:at:)` takes the answer.
        case check(UUID, ImportCandidate)
        /// Drop what runs for this row: its import's stream, which cancels it, or its check.
        case cancel(UUID)
        /// Say this in a plain toast.
        case toast(ImportToast)
    }

    public private(set) var rows: [Row] = []

    /// The imports that finished or failed since the list was last quiet. Their rows
    /// leave after a while, and the count on the status line must not shrink with them.
    private var done = 0

    public init() {}

    /// Whether an import is running: the status line says so.
    public var isRunning: Bool {
        rows.contains(where: \.state.isRunning)
    }

    /// The running import's place and how many there are, done or to do, since the
    /// list was last quiet: "Importing 2 of 5". Nil when nothing is running.
    public var progress: (position: Int, count: Int)? {
        guard isRunning else { return nil }
        let toDo = rows.count { $0.state.isRunning || $0.state == .waiting }
        return (done + 1, done + toDo)
    }

    /// New rows go to the end, and each is looked for in the library at once but
    /// the one that starts, which its import looks for first. A file whose row is
    /// still waiting, running or failed is refused and says so: that row is the
    /// one to watch, or retry. `ids` are the rows' identities, one per candidate.
    public mutating func enqueue(_ candidates: [ImportCandidate], ids: [UUID]) -> [Effect] {
        precondition(candidates.count == ids.count, "one id per candidate")
        var refusals: [Effect] = []
        var added: [UUID] = []
        for (id, candidate) in zip(ids, candidates) {
            if rows.contains(where: { $0.isPending && $0.candidate.isSameFile(as: candidate) }) {
                refusals.append(.toast(.alreadyListed(name: candidate.name)))
            } else {
                rows.append(Row(id: id, candidate: candidate, state: .waiting))
                added.append(id)
            }
        }
        let started = startNext()
        let checks: [Effect] = rows.filter { added.contains($0.id) && $0.state == .waiting }.map { .check($0.id, $0.candidate) }
        return refusals + started + checks
    }

    /// The library check's answer for a row: the wallpaper its source file already
    /// is, or nil. A waiting row the library has is a duplicate at once and leaves
    /// as a finished row does; it is no import, so the count leaves it out. Any
    /// other row is left as it is: a running import finds out for itself.
    public mutating func checked(_ id: UUID, existing: Wallpaper?, at date: Date) -> [Effect] {
        guard let existing, let index = rows.firstIndex(where: { $0.id == id }), rows[index].state == .waiting else { return [] }
        rows[index].state = .duplicate(of: existing, at: date)
        return [.toast(.duplicate(of: existing))]
    }

    /// What the running row's stream said. Anything for a row that is not running is late, and changes nothing.
    public mutating func received(_ event: ImportEvent, for id: UUID, at date: Date) -> [Effect] {
        guard let index = rows.firstIndex(where: { $0.id == id }), rows[index].state.isRunning else { return [] }
        var said: [Effect] = []
        switch event {
        case .progress(let progress):
            rows[index].state = .running(stage: progress.stage, words: stageWords(progress.stage), fraction: progress.fraction)
            return []
        case .finished(.imported(let wallpaper, _)), .finished(.importedScene(let wallpaper, _, _)):
            rows[index].state = .finished(wallpaper, at: date)
        case .finished(.duplicate(let wallpaper)):
            rows[index].state = .duplicate(of: wallpaper, at: date)
            said = [.toast(.duplicate(of: wallpaper))]
        }
        done += 1
        return said + startNext()
    }

    /// The running row's stream threw. A cancel is not a failure: the row goes,
    /// saying nothing. A failure says why in a toast; its row stays until Retry or
    /// `cancel` when Retry can help, and leaves as a finished row does (`tick`) when it cannot.
    public mutating func failed(_ id: UUID, error: any Error, at date: Date) -> [Effect] {
        guard let index = rows.firstIndex(where: { $0.id == id }), rows[index].state.isRunning else { return [] }
        var said: [Effect] = []
        if error is CancellationError {
            rows.remove(at: index)
        } else {
            let words = importFailureWords(error)
            rows[index].state = .failed(reason: words.reason, canRetry: words.canRetry, at: date)
            said = [.toast(.failed(name: rows[index].candidate.name, error: error))]
            done += 1
        }
        return said + startNext()
    }

    /// Takes the row away, whatever its state: a failed row is simply dismissed,
    /// and what runs for a waiting or running one is dropped.
    public mutating func cancel(_ id: UUID) -> [Effect] {
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return [] }
        let removed = rows.remove(at: index)
        return removed.state.canCancel ? [.cancel(id)] + startNext() : []
    }

    /// A failed row waits again where it is. The list runs top to bottom, so it goes before the rows below it.
    public mutating func retry(_ id: UUID) -> [Effect] {
        guard let index = rows.firstIndex(where: { $0.id == id }), case .failed = rows[index].state else { return [] }
        rows[index].state = .waiting
        return startNext()
    }

    /// Finished and duplicate rows leave `finishedLifetime` after they finished, and so
    /// does a failed row that Retry cannot help. One that Retry can help stays for it.
    public mutating func tick(at date: Date) -> [Effect] {
        rows.removeAll { $0.leavesAt.map { $0 <= date } ?? false }
        return []
    }

    /// When a tick next has something to do, for the caller to schedule one.
    public var nextTick: Date? {
        rows.compactMap(\.leavesAt).min()
    }

    /// Starts the first waiting row, unless one is running. With none left, the list is quiet and the count starts again.
    private mutating func startNext() -> [Effect] {
        guard !isRunning else { return [] }
        guard let next = rows.firstIndex(where: { $0.state == .waiting }) else {
            done = 0
            return []
        }
        rows[next].state = .running(stage: .fingerprint, words: stageWords(.fingerprint), fraction: nil)
        return [.start(rows[next].id, rows[next].candidate)]
    }
}

// What a row offers, read by the list under the grid.
extension ImportList.RowState {
    public var isRunning: Bool {
        if case .running = self { true } else { false }
    }

    /// Waiting or running: its Cancel takes it off the list and stops it.
    public var canCancel: Bool {
        switch self {
        case .waiting, .running: true
        case .finished, .duplicate, .failed: false
        }
    }

    /// Only where Retry can help: the cause lay outside the file.
    public var canRetry: Bool {
        if case .failed(_, let canRetry, _) = self { canRetry } else { false }
    }

    /// A row that stays until the user acts on it, a failure Retry can help, is
    /// taken off the list from its menu. Every other row leaves by itself.
    public var canRemove: Bool { canRetry }

    /// The wallpaper a finished row made, or already was: its poster stands in the row.
    public var wallpaper: Wallpaper? {
        switch self {
        case .finished(let wallpaper, _), .duplicate(let wallpaper, _): wallpaper
        case .waiting, .running, .failed: nil
        }
    }
}

extension ImportList.Row {
    /// On the list and not done with: a file dropped again while it is waiting,
    /// running or failed is this row's, not a new one.
    fileprivate var isPending: Bool {
        switch state {
        case .waiting, .running, .failed: true
        case .finished, .duplicate: false
        }
    }

    fileprivate var leavesAt: Date? {
        switch state {
        case .finished(_, let date), .duplicate(_, let date), .failed(_, canRetry: false, let date):
            date.addingTimeInterval(ImportList.finishedLifetime / .seconds(1))
        case .waiting, .running, .failed(_, canRetry: true, _): nil
        }
    }
}

extension ImportCandidate {
    /// The same source file, however its URL was spelt.
    fileprivate func isSameFile(as other: ImportCandidate) -> Bool {
        source.standardizedFileURL.path == other.source.standardizedFileURL.path
    }
}
