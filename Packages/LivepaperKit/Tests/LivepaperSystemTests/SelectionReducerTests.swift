import Foundation
import LivepaperCore
import LivepaperSystem
import Testing

/// Selecting and leaving as events in and effects out, with the times written
/// in seconds after the select was asked for.
struct SelectionReducerTests {
    static let wrote = WallpaperStoreEdit(changed: 2, desktopEntries: 2, keptCopy: true)
    static let unchanged = WallpaperStoreEdit(changed: 0, desktopEntries: 2)
    static let restarted = AgentRestartOutcome.restarted(previous: 100, current: 101)

    /// A select asked for at launch, pluginkit listing the extension and the store written.
    static func selectingAndWritten() -> SelectionReducer {
        var reducer = SelectionReducer()
        _ = reducer.reduce(.select(at: Moment.launch, host: .notSelected))
        _ = reducer.reduce(.listed(true))
        _ = reducer.reduce(.edited(.success(wrote)))
        return reducer
    }

    // MARK: Selecting

    @Test func `select checks pluginkit, writes, restarts the agent once, and is selected on live`() {
        var reducer = SelectionReducer()
        #expect(reducer.reduce(.select(at: Moment.launch, host: .notSelected)) == [.checkListed])
        #expect(reducer.outcome == .working)
        #expect(reducer.deadline == Moment.after(30))
        #expect(reducer.reduce(.listed(true)) == [.writeSelection])
        #expect(reducer.reduce(.edited(.success(Self.wrote))) == [.restartAgent])
        #expect(reducer.reduce(.agentRestarted(Self.restarted)).isEmpty)
        #expect(reducer.reduce(.host(.connecting, at: Moment.after(1))).isEmpty)
        #expect(reducer.outcome == .working)

        #expect(reducer.reduce(.host(.live, at: Moment.after(1.5))) == [.reportLive(after: .seconds(1.5))])
        #expect(reducer.outcome == .selected)
        #expect(reducer.deadline == nil)
    }

    @Test func `live may come before the restart has answered, which then changes nothing`() {
        var reducer = Self.selectingAndWritten()

        #expect(reducer.reduce(.host(.live, at: Moment.after(0.3))) == [.reportLive(after: .seconds(0.3))])
        #expect(reducer.reduce(.agentRestarted(Self.restarted)).isEmpty)
        #expect(reducer.outcome == .selected)
    }

    @Test func `still waiting just before 30 s`() {
        var reducer = Self.selectingAndWritten()
        _ = reducer.reduce(.agentRestarted(Self.restarted))

        #expect(reducer.reduce(.tick(at: Moment.after(29.9))).isEmpty)
        #expect(reducer.outcome == .working)
        #expect(reducer.deadline == Moment.after(30))
    }

    @Test func `no live within 30 s opens the pane, and the user's click there finishes it`() {
        var reducer = Self.selectingAndWritten()
        _ = reducer.reduce(.agentRestarted(Self.restarted))

        #expect(reducer.reduce(.tick(at: Moment.after(30))) == [.openPane(.noLiveInTime)])
        #expect(reducer.outcome == .chooseInPane(.noLiveInTime))
        #expect(reducer.deadline == nil)
        #expect(reducer.reduce(.paneOpened(true)).isEmpty)

        #expect(reducer.reduce(.host(.live, at: Moment.after(52))) == [.reportLive(after: .seconds(52))])
        #expect(reducer.outcome == .selected)
    }

    @Test func `already live writes nothing and asks nothing`() {
        var reducer = SelectionReducer()
        #expect(reducer.reduce(.select(at: Moment.launch, host: .live)) == [.reportAlreadyLive])
        #expect(reducer.outcome == .selected)
        #expect(reducer.deadline == nil)
    }

    @Test func `a store already naming Livepaper everywhere restarts nothing and completes on the flag`() {
        var reducer = SelectionReducer()
        _ = reducer.reduce(.select(at: Moment.launch, host: .connecting))
        _ = reducer.reduce(.listed(true))

        #expect(reducer.reduce(.edited(.success(Self.unchanged))).isEmpty)
        #expect(reducer.outcome == .working)
        #expect(reducer.reduce(.host(.live, at: Moment.after(2))) == [.reportLive(after: .seconds(2))])
        #expect(reducer.outcome == .selected)
    }

    @Test func `a store already naming Livepaper everywhere, with no live in 30 s, opens the pane`() {
        var reducer = SelectionReducer()
        _ = reducer.reduce(.select(at: Moment.launch, host: .connecting))
        _ = reducer.reduce(.listed(true))
        _ = reducer.reduce(.edited(.success(Self.unchanged)))

        #expect(reducer.reduce(.tick(at: Moment.after(30))) == [.openPane(.noLiveInTime)])
    }

    @Test func `an extension pluginkit does not list opens the pane at once, and nothing is written`() {
        var reducer = SelectionReducer()
        _ = reducer.reduce(.select(at: Moment.launch, host: .connecting))

        #expect(reducer.reduce(.listed(false)) == [.openPane(.notListed)])
        #expect(reducer.outcome == .chooseInPane(.notListed))
        #expect(reducer.deadline == nil)
    }

    static let storeErrors: [WallpaperStoreError] = [
        .unreadable(.store),
        .unknownShape(.store, .noPlaces),
        .unknownShape(.store, .unexpected(at: "SystemDefault.Desktop")),
        .notWritten(.keptCopy),
        .notWritten(.store),
    ]

    @Test(arguments: storeErrors)
    func `a store that cannot be read, or is of a shape this build does not know, opens the pane`(error: WallpaperStoreError) {
        var reducer = SelectionReducer()
        _ = reducer.reduce(.select(at: Moment.launch, host: .connecting))
        _ = reducer.reduce(.listed(true))

        #expect(reducer.reduce(.edited(.failure(error))) == [.openPane(.store(error))])
        #expect(reducer.outcome == .chooseInPane(.store(error)))
    }

    @Test func `answers that come after the pane opened change nothing`() {
        var reducer = SelectionReducer()
        _ = reducer.reduce(.select(at: Moment.launch, host: .connecting))
        _ = reducer.reduce(.tick(at: Moment.after(30)))

        #expect(reducer.reduce(.listed(true)).isEmpty)
        #expect(reducer.reduce(.edited(.success(Self.wrote))).isEmpty)
        #expect(reducer.reduce(.agentRestarted(Self.restarted)).isEmpty)
        #expect(reducer.outcome == .chooseInPane(.noLiveInTime))
    }

    @Test func `a second select while one runs changes nothing`() {
        var reducer = SelectionReducer()
        _ = reducer.reduce(.select(at: Moment.launch, host: .connecting))

        #expect(reducer.reduce(.select(at: Moment.after(5), host: .connecting)).isEmpty)
        #expect(reducer.reduce(.leave).isEmpty)
        #expect(reducer.deadline == Moment.after(30))
    }

    @Test func `select again from the pane starts over, with 30 s of its own`() {
        var reducer = SelectionReducer()
        _ = reducer.reduce(.select(at: Moment.launch, host: .connecting))
        _ = reducer.reduce(.listed(false))

        #expect(reducer.reduce(.select(at: Moment.after(60), host: .notSelected)) == [.checkListed])
        #expect(reducer.deadline == Moment.after(90))
    }

    @Test func `a pane that will not open is a failure, and a click in System Settings still finishes it`() {
        var reducer = SelectionReducer()
        _ = reducer.reduce(.select(at: Moment.launch, host: .connecting))
        _ = reducer.reduce(.listed(false))

        #expect(reducer.reduce(.paneOpened(false)).isEmpty)
        #expect(reducer.outcome == .failed(.notListed, leaving: false))
        #expect(reducer.reduce(.host(.live, at: Moment.after(90))) == [.reportLive(after: .seconds(90))])
        #expect(reducer.outcome == .selected)
    }

    @Test func `once selected, the host going quiet or unselected is not the selection's business`() {
        var reducer = SelectionReducer()
        _ = reducer.reduce(.select(at: Moment.launch, host: .live))

        #expect(reducer.reduce(.host(.notSelected, at: Moment.after(5))).isEmpty)
        #expect(reducer.reduce(.tick(at: Moment.after(30))).isEmpty)
        #expect(reducer.outcome == .selected)
    }

    // MARK: Leaving

    @Test func `a leave writes once, restarts once, then the kept copy goes`() {
        var reducer = SelectionReducer()
        #expect(reducer.reduce(.leave) == [.writeDeselection])
        #expect(reducer.outcome == .working)
        #expect(reducer.reduce(.edited(.success(Self.wrote))) == [.restartAgent])
        #expect(reducer.reduce(.host(.live, at: Moment.after(1))).isEmpty)
        #expect(reducer.outcome == .working)

        #expect(reducer.reduce(.agentRestarted(Self.restarted)) == [.removeKeptCopy])
        #expect(reducer.outcome == .left)
        #expect(reducer.deadline == nil)
    }

    @Test func `a leave where Livepaper is named nowhere restarts nothing, and the copy goes`() {
        var reducer = SelectionReducer()
        _ = reducer.reduce(.leave)

        #expect(reducer.reduce(.edited(.success(Self.unchanged))) == [.removeKeptCopy])
        #expect(reducer.outcome == .left)
    }

    @Test(arguments: [WallpaperStoreError.noKeptCopy, .nothingToGoBackTo, .unknownShape(.keptCopy, .notADictionary), .unreadable(.store)])
    func `a leave with no usable copy opens the pane for another wallpaper`(error: WallpaperStoreError) {
        var reducer = SelectionReducer()
        _ = reducer.reduce(.leave)

        #expect(reducer.reduce(.edited(.failure(error))) == [.openPane(.store(error))])
        #expect(reducer.outcome == .chooseAnotherInPane(.store(error)))
        #expect(reducer.reduce(.paneOpened(false)).isEmpty)
        #expect(reducer.outcome == .failed(.store(error), leaving: true))
    }

    @Test func `a leave stops a select waiting in the pane`() {
        var reducer = SelectionReducer()
        _ = reducer.reduce(.select(at: Moment.launch, host: .connecting))
        _ = reducer.reduce(.listed(false))

        #expect(reducer.reduce(.leave) == [.writeDeselection])
        #expect(reducer.reduce(.host(.live, at: Moment.after(40))).isEmpty)
    }

    // MARK: Words

    @Test func `the pane's words name the tile to choose`() {
        #expect(SelectionOutcome.chooseInPane(.noLiveInTime).words == "System Settings is open at Wallpaper: choose “Livepaper” there.")
        #expect(
            SelectionOutcome.failed(.notListed, leaving: false).words == "Open System Settings, go to Wallpaper and choose “Livepaper”."
        )
        #expect(SelectionOutcome.chooseAnotherInPane(.store(.noKeptCopy)).words?.contains("Livepaper") == false)
        #expect(SelectionOutcome.selected.words == nil)
    }
}
