import Foundation
import LivepaperCore
import LivepaperSystem

/// What the fakes were asked to do, in the order they were asked.
@MainActor
final class Journal {
    private(set) var entries: [String] = []

    func note(_ entry: String) {
        entries.append(entry)
    }
}

/// A render host's status, reported by the test.
@MainActor
final class FakeHostStatus: HostStatusSource {
    private(set) var currentStatus: RenderHostStatus
    private let broadcast = Broadcast<RenderHostStatus>(bufferingPolicy: .unbounded)

    init(_ status: RenderHostStatus) {
        currentStatus = status
        broadcast.send(status)
    }

    var status: AsyncStream<RenderHostStatus> { broadcast.stream() }

    /// How many streams are being read.
    var readerCount: Int { broadcast.readerCount }

    /// A heartbeat changing the status, as the real host reports it.
    func report(_ status: RenderHostStatus) {
        currentStatus = status
        broadcast.send(status)
    }
}

@MainActor
final class FakeExtensionListing: ExtensionListing {
    var listed = true
    private let journal: Journal

    init(journal: Journal) {
        self.journal = journal
    }

    func isListed(_ bundleIdentifier: String) async -> Bool {
        journal.note("pluginkit \(bundleIdentifier)")
        return listed
    }
}

/// A store that is never written, answering what the test says.
@MainActor
final class FakeStoreEditor: WallpaperStoreEditing {
    typealias Answer = Result<WallpaperStoreEdit, WallpaperStoreError>

    var selectAnswer = Answer.success(WallpaperStoreEdit(changed: 2, desktopEntries: 2, keptCopy: true))
    var deselectAnswer = Answer.success(WallpaperStoreEdit(changed: 2, desktopEntries: 2))
    private(set) var selectedAt: [Date] = []
    private let journal: Journal

    init(journal: Journal) {
        self.journal = journal
    }

    func select(at now: Date) throws(WallpaperStoreError) -> WallpaperStoreEdit {
        journal.note("select")
        selectedAt.append(now)
        return try selectAnswer.get()
    }

    func deselect() throws(WallpaperStoreError) -> WallpaperStoreEdit {
        journal.note("deselect")
        return try deselectAnswer.get()
    }

    func removeKeptCopy() {
        journal.note("remove kept copy")
    }
}

/// Restarts nothing, and says when it was asked to.
@MainActor
final class JournalingAgentRestarter: AgentRestarting {
    private(set) var restarts = 0
    /// Yields the number of each restart as it is asked for.
    let asked: AsyncStream<Int>
    private let continuation: AsyncStream<Int>.Continuation
    private let journal: Journal

    init(journal: Journal) {
        self.journal = journal
        (asked, continuation) = AsyncStream.makeStream()
    }

    func restartAgent() async -> AgentRestartOutcome {
        restarts += 1
        journal.note("restart")
        continuation.yield(restarts)
        return .restarted(previous: 100, current: 101)
    }
}

@MainActor
final class FakeWallpaperPane: WallpaperPaneOpening {
    var opens = true
    private let journal: Journal

    init(journal: Journal) {
        self.journal = journal
    }

    func openWallpaperPane() -> Bool {
        journal.note("open pane")
        return opens
    }
}
