import Foundation
import LivepaperCore
import LivepaperSystem
import os
import Testing

// Some tests wait on the selection's streams; one that never yields fails the test instead of hanging the run.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SelectionTests {
    static let extensionID = WallpaperExtensionIdentity.bundleIdentifier

    let journal = Journal()
    let clock = ManualWallClock()
    let restarts = MemoryAgentRestartStore()
    let host: FakeHostStatus
    let extensions: FakeExtensionListing
    let store: FakeStoreEditor
    let agent: JournalingAgentRestarter
    let pane: FakeWallpaperPane

    init() {
        host = FakeHostStatus(.notSelected)
        extensions = FakeExtensionListing(journal: journal)
        store = FakeStoreEditor(journal: journal)
        agent = JournalingAgentRestarter(journal: journal)
        pane = FakeWallpaperPane(journal: journal)
    }

    func selection(store: any WallpaperStoreEditing) -> Selection {
        Selection(
            host: host, store: store, extensions: extensions, agent: agent, restartStore: restarts, pane: pane, clock: clock,
            logger: Logger(subsystem: "app.livepaper.tests", category: SelectionLog.category)
        )
    }

    func selection() -> Selection {
        selection(store: store)
    }

    /// Lets the selection's own tasks run until `condition` holds, or gives up.
    func settle(until condition: () -> Bool) async {
        for _ in 0..<100 where !condition() {
            await Task.yield()
        }
    }

    // MARK: Selecting

    @Test func `select checks pluginkit, writes once, restarts once, and is selected on live`() async {
        let selection = selection()
        let selecting = Task { await selection.select() }
        var asked = agent.asked.makeAsyncIterator()
        #expect(await asked.next() == 1)

        host.report(.live)

        #expect(await selecting.value == .selected)
        #expect(journal.entries == ["pluginkit \(Self.extensionID)", "select", "restart"])
        #expect(store.selectedAt == [Moment.launch])
        #expect(clock.scheduled.isEmpty)
        await settle { host.readerCount == 0 }
        #expect(host.readerCount == 0, "a selection that is done stops reading the host")
    }

    @Test func `the restart is recorded, so that the host's ladder counts its ten minutes from it`() async {
        let selection = selection()
        clock.advance(toSecond: 12)
        let selecting = Task { await selection.select() }
        var asked = agent.asked.makeAsyncIterator()
        _ = await asked.next()
        host.report(.live)
        _ = await selecting.value

        #expect(restarts.lastRestart == Moment.after(12))
    }

    @Test func `with no live in 30 s the pane opens, and the user's click there finishes it`() async {
        let selection = selection()
        let selecting = Task { await selection.select() }
        var asked = agent.asked.makeAsyncIterator()
        _ = await asked.next()
        #expect(clock.scheduled == [Moment.after(30)])

        clock.advance(toSecond: 30)

        #expect(await selecting.value == .chooseInPane(.noLiveInTime))
        #expect(journal.entries.last == "open pane")
        var outcomes = selection.outcomes.makeAsyncIterator()
        #expect(await outcomes.next() == .chooseInPane(.noLiveInTime))
        host.report(.live)
        #expect(await outcomes.next() == .selected)
        #expect(agent.restarts == 1)
    }

    @Test func `already live writes nothing and asks nothing`() async {
        host.report(.live)
        let selection = selection()

        #expect(await selection.select() == .selected)
        #expect(journal.entries.isEmpty)
        #expect(clock.scheduled.isEmpty)
        #expect(restarts.lastRestart == nil)
    }

    @Test func `a store already naming Livepaper everywhere restarts nothing and completes on the flag`() async {
        store.selectAnswer = .success(WallpaperStoreEdit(changed: 0, desktopEntries: 2))
        let selection = selection()
        let selecting = Task { await selection.select() }
        await settle { journal.entries.contains("select") }

        host.report(.live)

        #expect(await selecting.value == .selected)
        #expect(journal.entries == ["pluginkit \(Self.extensionID)", "select"])
        #expect(restarts.lastRestart == nil)
    }

    @Test func `an extension pluginkit does not list opens the pane, and nothing is written`() async {
        extensions.listed = false
        let selection = selection()

        #expect(await selection.select() == .chooseInPane(.notListed))
        #expect(journal.entries == ["pluginkit \(Self.extensionID)", "open pane"])
        #expect(clock.scheduled.isEmpty)
        #expect(host.readerCount == 1, "the click in the pane is still waited for")
    }

    @Test func `an unreadable store opens the pane, and the agent is left alone`() async {
        store.selectAnswer = .failure(.unreadable(.store))
        let selection = selection()

        #expect(await selection.select() == .chooseInPane(.store(.unreadable(.store))))
        #expect(journal.entries == ["pluginkit \(Self.extensionID)", "select", "open pane"])
    }

    @Test func `a pane that will not open is a failure, with the words to go there`() async {
        extensions.listed = false
        pane.opens = false
        let selection = selection()

        let outcome = await selection.select()

        #expect(outcome == .failed(.notListed, leaving: false))
        #expect(outcome.words == "Open System Settings, go to Wallpaper and choose “Livepaper”.")
    }

    @Test func `a second select while one runs joins it`() async {
        let selection = selection()
        let first = Task { await selection.select() }
        let second = Task { await selection.select() }
        var asked = agent.asked.makeAsyncIterator()
        _ = await asked.next()

        host.report(.live)

        #expect(await first.value == .selected)
        #expect(await second.value == .selected)
        #expect(agent.restarts == 1)
    }

    // MARK: Leaving

    @Test func `a leave writes once, restarts once, then the kept copy goes`() async {
        let selection = selection()

        #expect(await selection.leave() == .left)
        #expect(journal.entries == ["deselect", "restart", "remove kept copy"])
        #expect(restarts.lastRestart == Moment.launch)
    }

    @Test func `a leave with no usable copy opens the pane, and restarts nothing`() async {
        store.deselectAnswer = .failure(.noKeptCopy)
        let selection = selection()

        #expect(await selection.leave() == .chooseAnotherInPane(.store(.noKeptCopy)))
        #expect(journal.entries == ["deselect", "open pane"])
    }

    // MARK: On a copy of a real store

    @Test func `select, then leave, on a copy of a real store: the Aerial comes back and the copy goes`() async throws {
        let home = try TemporaryFolder()
        let real = WallpaperStore(home: home.url)
        try FileManager.default.createDirectory(at: real.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Fixture.data(Fixture.aerial).write(to: real.file)
        let selection = selection(store: real)
        let selecting = Task { await selection.select() }
        var asked = agent.asked.makeAsyncIterator()
        _ = await asked.next()
        host.report(.live)
        #expect(await selecting.value == .selected)
        #expect(real.shape() == WallpaperStoreShape(store: .read(desktopEntries: 2, namingLivepaper: 2), keptCopyExists: true))

        #expect(await selection.leave() == .left)

        #expect(try StoreTree(contentsOf: real.file) == StoreTree(data: Fixture.data(Fixture.aerial)))
        #expect(!FileManager.default.fileExists(atPath: real.keptCopy.path))
        #expect(agent.restarts == 2)
    }
}

/// Other checks read these lines (the onboarding check on screen, the beta-seed checklist), so their wording is pinned.
struct SelectionLogTests {
    static let rows: [Row<String, String>] = [
        Row(
            "the store written, and kept",
            SelectionLog.selected(WallpaperStoreEdit(changed: 2, desktopEntries: 2, keptCopy: true)),
            "selection: store written, 2 of 2 Desktop entries now name Livepaper; the store as it was kept"
        ),
        Row(
            "the store already selected",
            SelectionLog.selected(WallpaperStoreEdit(changed: 0, desktopEntries: 24)),
            "selection: store already names Livepaper in all 24 Desktop entries, nothing written"
        ),
        Row(
            "the store put back",
            SelectionLog.deselected(WallpaperStoreEdit(changed: 2, desktopEntries: 2)),
            "selection: store written, 2 Desktop entries put back from the kept copy"
        ),
        Row("the agent restarting", SelectionLog.restarting, "selection: restarting WallpaperAgent"),
        Row(
            "the agent restarted",
            SelectionLog.restarted(.restarted(previous: 62873, current: 61187)),
            "selection: WallpaperAgent restarted, pid 62873 -> 61187"
        ),
        Row("live, and how long it took", SelectionLog.live(after: .milliseconds(270)), "selection: live 0.27 s after asking"),
        Row("already live", SelectionLog.alreadyLive, "selection: already live, nothing written"),
        Row(
            "the pane, for pluginkit",
            SelectionLog.fallback(.notListed),
            "selection: opening System Settings at Wallpaper: pluginkit does not list the extension"
        ),
        Row(
            "the pane, for no heartbeat",
            SelectionLog.fallback(.noLiveInTime),
            "selection: opening System Settings at Wallpaper: no heartbeat with a desktop surface within 30 s"
        ),
        Row(
            "the pane, for a store of a shape this build does not know",
            SelectionLog.fallback(.store(.unknownShape(.store, .unexpected(at: "SystemDefault.Desktop")))),
            "selection: opening System Settings at Wallpaper: the wallpaper store is of a shape this build does not know "
                + "(unexpected at SystemDefault.Desktop)"
        ),
        Row(
            "the pane, for no kept copy",
            SelectionLog.fallback(.store(.noKeptCopy)),
            "selection: opening System Settings at Wallpaper: no copy of the store was kept"
        ),
    ]

    @Test(arguments: rows)
    func `each line reads as the checks expect`(row: Row<String, String>) {
        #expect(row.input == row.expected)
    }
}
