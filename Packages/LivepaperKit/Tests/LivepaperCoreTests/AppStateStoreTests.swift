import Foundation
import Testing
import LivepaperCore

/// Every test gets its own folder under the temporary directory, removed afterwards.
final class AppStateStoreTests {
    let directory: URL
    let store: FileAppStateStore

    init() {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "LivepaperCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        store = FileAppStateStore(file: directory.appending(path: "Livepaper/app-state.json"))
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    private func write(_ contents: Data) throws {
        try FileManager.default.createDirectory(at: store.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: store.file)
    }

    private func written() throws -> [String] {
        try FileManager.default.subpathsOfDirectory(atPath: directory.path).sorted()
    }

    static let newerMajor = Data(#"{"version":{"major":2,"minor":0},"displays":{}}"#.utf8)

    // MARK: Load and save

    @Test func `a first launch, with no folder yet, finds no state`() {
        #expect(store.load() == .missing)
    }

    @Test func `a saved state loads again`() throws {
        try store.save(AppStateTests.fixtureState)

        #expect(store.load() == .loaded(AppStateTests.fixtureState))
    }

    @Test func `each save replaces the one before`() throws {
        var muted = AppState()
        muted.isMuted = true

        try store.save(AppState())
        try store.save(muted)

        #expect(store.load() == .loaded(muted))
    }

    @Test func `the version 1.0 fixture loads`() throws {
        try write(Fixture.data("app-state-v1.0"))

        #expect(store.load() == .loaded(AppStateTests.fixtureState))
    }

    @Test func `the version 1.1 fixture loads`() throws {
        try write(Fixture.data("app-state-v1.1"))

        #expect(store.load() == .loaded(AppStateLoginAndHotkeysTests.fixtureState))
    }

    @Test func `a save writes the one file and leaves nothing beside it`() throws {
        try store.save(AppStateTests.fixtureState)
        try store.save(AppState())

        #expect(try written() == ["Livepaper", "Livepaper/app-state.json"])
        #expect(try Data(contentsOf: store.file) == AppState().encode())
    }

    // MARK: Failing closed

    @Test func `a state from an unknown major version is kept aside, and the app starts on defaults`() throws {
        try write(Self.newerMajor)

        #expect(store.load() == .keptAside(store.keptAside, SchemaVersion(major: 2, minor: 0)))
        #expect(try Data(contentsOf: store.keptAside) == Self.newerMajor)
        #expect(!FileManager.default.fileExists(atPath: store.file.path))
    }

    @Test func `the next save never overwrites a state kept aside`() throws {
        try write(Self.newerMajor)
        _ = store.load()

        try store.save(AppState())

        #expect(try Data(contentsOf: store.keptAside) == Self.newerMajor)
        #expect(store.load() == .loaded(AppState()))
    }

    static let damage: [Row<Data, Void>] = [
        Row("cut short", Data(#"{"version":{"major":1,"minor":0},"assignm"#.utf8), ()),
        Row("cut down to nothing", Data(), ()),
        Row("overwritten with something that is not a state", Data("[]".utf8), ()),
    ]

    @Test(arguments: damage)
    func `a damaged state is kept aside, and the app starts on defaults`(row: Row<Data, Void>) throws {
        try write(row.input)

        #expect(store.load() == .keptAside(store.keptAside, nil))
        #expect(try Data(contentsOf: store.keptAside) == row.input)
    }

    @Test func `a state kept aside replaces the one kept aside before`() throws {
        try write(Data("[]".utf8))
        _ = store.load()
        try write(Self.newerMajor)
        _ = store.load()

        #expect(try Data(contentsOf: store.keptAside) == Self.newerMajor)
        #expect(try written() == ["Livepaper", "Livepaper/app-state.kept-aside.json"])
    }
}
