import Foundation
import Testing
import LivepaperImport
import LivepaperWorkshop

/// The Workshop items being got, one steamcmd at a time, and handed to the import once downloaded.
struct WorkshopDownloadsTests {
    typealias Effect = WorkshopDownloads.Effect

    static let cat = WorkshopItemID(3_289_988_463)!
    static let rain = WorkshopItemID(1_111)!
    static let lanterns = WorkshopItemID(2_222)!
    static let folder = URL(filePath: "/Users/someone/Library/Application Support/Steam/steamapps/workshop/content/431960/3289988463")

    static func states(_ list: WorkshopDownloads) -> [WorkshopDownloads.State] {
        list.rows.map(\.state)
    }

    @Test func `one item is got at a time, in the order asked`() {
        var list = WorkshopDownloads()
        #expect(list.get(Self.cat, title: "Lonely Cat") == [.start(Self.cat)])
        #expect(list.get(Self.rain, title: "Rain") == [])
        #expect(Self.states(list) == [.starting, .waiting])
        #expect(list.rows.map(\.title) == ["Lonely Cat", "Rain"])
    }

    @Test func `an item with no title from its page is called by its number`() {
        var list = WorkshopDownloads()
        _ = list.get(Self.cat, title: nil)
        #expect(list.rows.first?.title == "Workshop item 3289988463")
    }

    @Test func `the row follows steamcmd`() {
        var list = WorkshopDownloads()
        _ = list.get(Self.cat, title: "Lonely Cat")
        list.progress(Self.cat, .updating(percent: 0))
        #expect(Self.states(list) == [.starting])
        list.progress(Self.cat, .updating(percent: 40))
        #expect(Self.states(list) == [.settingUp(percent: 40)])
        list.progress(Self.cat, .signingIn)
        #expect(Self.states(list) == [.signingIn])
        list.progress(Self.cat, .downloading)
        #expect(Self.states(list) == [.downloading])
    }

    @Test func `a download is looked into, then handed to the import, and the next one starts`() {
        var list = WorkshopDownloads()
        _ = list.get(Self.cat, title: "Lonely Cat")
        _ = list.get(Self.rain, title: "Rain")
        #expect(list.downloaded(Self.cat, folder: Self.folder) == [.discover(Self.cat, folder: Self.folder)])
        list.progress(Self.cat, .downloading)
        #expect(Self.states(list) == [.opening, .waiting])
        #expect(list.discovered(Self.cat, .importable) == [.importFolder(Self.folder), .start(Self.rain)])
        #expect(list.rows.map(\.item) == [Self.rain])
    }

    @Test func `a download discovery passes over fails with the import's reason, and stays`() {
        var list = WorkshopDownloads()
        _ = list.get(Self.cat, title: "A Web Page")
        _ = list.downloaded(Self.cat, folder: Self.folder)
        #expect(list.discovered(Self.cat, .skipped(.wallpaperEngine(.runsCode("web")))) == [])
        #expect(Self.states(list) == [.failed(.refused(.skipped(.wallpaperEngine(.runsCode("web")))))])
    }

    @Test func `a download with nothing in it to import says so`() {
        var list = WorkshopDownloads()
        _ = list.get(Self.cat, title: "Lonely Cat")
        _ = list.downloaded(Self.cat, folder: Self.folder)
        #expect(list.discovered(Self.cat, .nothing) == [])
        #expect(Self.states(list) == [.failed(.steam(.nothingToImport))])
    }

    static let discoveries: [Row<Discovery, DiscoveredItem>] = [
        Row(
            "an item the import can take",
            Discovery(candidates: [ImportCandidate(source: URL(filePath: "/a/scene.pkg"), name: "Lonely Cat")]),
            .importable
        ),
        Row(
            "an item discovery passes over",
            Discovery(skipped: [SkippedSource(url: URL(filePath: "/a"), reason: .wallpaperEngine(.runsCode("application")))]),
            .skipped(.wallpaperEngine(.runsCode("application")))
        ),
        Row("an empty folder", Discovery(), .nothing),
    ]

    @Test(arguments: discoveries)
    func `reads what discovery found in the folder`(row: Row<Discovery, DiscoveredItem>) {
        #expect(DiscoveredItem(row.input) == row.expected)
    }

    @Test func `an item its page refuses is not downloaded`() {
        var list = WorkshopDownloads()
        #expect(list.get(Self.cat, title: "A Web Page", refusal: .skipped(.wallpaperEngine(.runsCode("web")))) == [])
        #expect(Self.states(list) == [.failed(.refused(.skipped(.wallpaperEngine(.runsCode("web")))))])
        #expect(list.get(Self.rain, title: "Rain") == [.start(Self.rain)])
    }

    @Test func `a failure stays on the list with Steam's reason, and the next one starts`() {
        var list = WorkshopDownloads()
        _ = list.get(Self.cat, title: "Lonely Cat")
        _ = list.get(Self.rain, title: "Rain")
        #expect(list.failed(Self.cat, .notOwned) == [.start(Self.rain)])
        #expect(Self.states(list) == [.failed(.steam(.notOwned)), .starting])
    }

    @Test func `no saved login holds every item until the user signs in, then they go on`() {
        var list = WorkshopDownloads()
        _ = list.get(Self.cat, title: "Lonely Cat")
        _ = list.get(Self.rain, title: "Rain")
        #expect(list.failed(Self.cat, .signInNeeded) == [.askToSignIn])
        #expect(Self.states(list) == [.failed(.steam(.signInNeeded)), .failed(.steam(.signInNeeded))])
        #expect(list.get(Self.lanterns, title: "Lanterns") == [.askToSignIn])
        #expect(list.signedIn() == [.start(Self.cat)])
        #expect(Self.states(list) == [.starting, .waiting, .waiting])
    }

    @Test func `asking for an item already on the list does nothing, and retries a failed one`() {
        var list = WorkshopDownloads()
        _ = list.get(Self.cat, title: "Lonely Cat")
        #expect(list.get(Self.cat, title: "Lonely Cat") == [])
        _ = list.failed(Self.cat, .timedOut)
        #expect(list.get(Self.cat, title: "Lonely Cat") == [.start(Self.cat)])
        #expect(list.rows.count == 1)
    }

    @Test func `retry puts a failed item back in line, where it is`() {
        var list = WorkshopDownloads()
        _ = list.get(Self.cat, title: "Lonely Cat")
        _ = list.get(Self.rain, title: "Rain")
        _ = list.failed(Self.cat, .timedOut)
        #expect(list.retry(Self.cat) == [])
        #expect(Self.states(list) == [.waiting, .starting])
        #expect(list.rows.map(\.item) == [Self.cat, Self.rain])
    }

    @Test func `retry of an item held for sign-in asks for the sign-in`() {
        var list = WorkshopDownloads()
        _ = list.get(Self.cat, title: "Lonely Cat")
        _ = list.failed(Self.cat, .signInNeeded)
        #expect(list.retry(Self.cat) == [.askToSignIn])
        #expect(Self.states(list) == [.failed(.steam(.signInNeeded))])
    }

    @Test func `a failed row can be taken off the list`() {
        var list = WorkshopDownloads()
        _ = list.get(Self.cat, title: "Lonely Cat")
        _ = list.failed(Self.cat, .notOwned)
        #expect(list.cancel(Self.cat) == [])
        #expect(list.rows.isEmpty)
    }

    @Test func `cancelling the one running stops it and starts the next; a waiting one just goes`() {
        var list = WorkshopDownloads()
        _ = list.get(Self.cat, title: "Lonely Cat")
        _ = list.get(Self.rain, title: "Rain")
        _ = list.get(Self.lanterns, title: "Lanterns")
        #expect(list.cancel(Self.lanterns) == [])
        #expect(list.cancel(Self.cat) == [.cancel(Self.cat), .start(Self.rain)])
        #expect(list.rows.map(\.item) == [Self.rain])
    }

    @Test func `news of an item no longer running changes nothing`() {
        var list = WorkshopDownloads()
        _ = list.get(Self.cat, title: "Lonely Cat")
        _ = list.cancel(Self.cat)
        list.progress(Self.cat, .downloading)
        #expect(list.downloaded(Self.cat, folder: Self.folder) == [])
        #expect(list.failed(Self.cat, .timedOut) == [])
        #expect(list.rows.isEmpty)
    }

    static let words: [Row<WorkshopDownloads.State, String?>] = [
        Row("waiting its turn: the row says Waiting itself", .waiting, nil),
        Row("steamcmd starting", .starting, "Starting Steam’s download tool"),
        Row("steamcmd fetching an update of itself", .settingUp(percent: 40), "Updating Steam’s download tool"),
        Row("signing in with the saved login", .signingIn, "Signing in to Steam"),
        Row("downloading", .downloading, "Downloading from Steam"),
        Row("discovery reading the folder", .opening, "Opening the item"),
    ]

    @Test(arguments: words)
    func `says what the row is doing`(row: Row<WorkshopDownloads.State, String?>) {
        #expect(workshopStageWords(row.input) == row.expected)
    }

    @Test func `a problem's words and what helps are Steam's, or the import's`() {
        #expect(WorkshopProblem.steam(.notOwned).words == workshopFailureWords(.notOwned).reason)
        #expect(WorkshopProblem.steam(.timedOut).canRetry)
        #expect(WorkshopProblem.steam(.signInNeeded).needsSignIn)
        let web = SkipReason.wallpaperEngine(.runsCode("web"))
        #expect(WorkshopProblem.refused(.skipped(web)).words == skipWords(web))
        #expect(!WorkshopProblem.refused(.notWallpaperEngine).canRetry)
    }
}
