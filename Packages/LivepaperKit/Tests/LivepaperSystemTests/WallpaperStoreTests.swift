import Foundation
import LivepaperCore
import LivepaperSystem
import Testing

/// The store edit on copies of real stores (Fixtures/README.md), in a home folder of the test's own.
struct WallpaperStoreTests {
    static let livepaper = WallpaperExtensionIdentity.bundleIdentifier
    static let selectedAt = Moment.after(60)

    let home: TemporaryFolder
    let store: WallpaperStore

    init() throws {
        home = try TemporaryFolder()
        store = WallpaperStore(home: home.url)
    }

    /// Puts a fixture where the store is, and returns the tree it holds.
    @discardableResult
    func install(_ fixture: String) throws -> StoreTree {
        try install(Fixture.data(fixture))
        return try StoreTree(data: Fixture.data(fixture))
    }

    func install(_ data: Data) throws {
        try FileManager.default.createDirectory(at: store.file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: store.file)
    }

    func onDisk() throws -> StoreTree {
        try StoreTree(contentsOf: store.file)
    }

    var keptCopyExists: Bool {
        FileManager.default.fileExists(atPath: store.keptCopy.path)
    }

    // MARK: Selecting

    @Test(arguments: [Fixture.spaces, Fixture.aerial])
    func `select rewrites every Desktop entry and no Idle entry`(fixture: String) throws {
        let before = try install(fixture)

        let edit = try store.select(at: Self.selectedAt)

        let after = try onDisk()
        let count = before.entries("Desktop").count
        #expect(edit == WallpaperStoreEdit(changed: count, desktopEntries: count, keptCopy: true))
        #expect(Set(after.desktopProviders.values) == [Self.livepaper])
        #expect(Set(after.desktopProviders.keys) == Set(before.desktopProviders.keys))
        #expect(StoreTree(after.entries("Idle")) == StoreTree(before.entries("Idle")))
        #expect(!after.entries("Idle").isEmpty)
    }

    @Test func `the 24 entries across 11 Spaces are all found`() throws {
        let before = try install(Fixture.spaces)

        #expect(before.entries("Desktop").count == 24)
        #expect(before.node(["Spaces"])?.count == 11)
    }

    @Test func `the entry written is the one WallpaperAgent writes when Livepaper is chosen, dates aside`() throws {
        try install(Fixture.aerial)
        let chosenByHand = try StoreTree(data: Fixture.data(Fixture.livepaper)).entries("Desktop")

        try store.select(at: Self.selectedAt)

        let written = try onDisk().entries("Desktop")
        #expect(written.keys.sorted() == chosenByHand.keys.sorted())
        for (place, entry) in written {
            let agents = try #require(chosenByHand[place])
            #expect(StoreTree(entry.filter { $0.key == "Content" }) == StoreTree(agents.filter { $0.key == "Content" }), "at \(place)")
            #expect(entry["LastSet"] as? Date == Self.selectedAt)
            #expect(entry["LastUse"] as? Date == Self.selectedAt)
        }
    }

    @Test func `the store is kept as it was, byte for byte, before it is written`() throws {
        try install(Fixture.spaces)

        try store.select(at: Self.selectedAt)

        #expect(try Data(contentsOf: store.keptCopy) == Fixture.data(Fixture.spaces))
    }

    @Test func `a store with no Desktop entry gets one at SystemDefault`() throws {
        let before = try install(Fixture.idleOnly)

        let edit = try store.select(at: Self.selectedAt)

        let after = try onDisk()
        #expect(edit == WallpaperStoreEdit(changed: 1, desktopEntries: 1, keptCopy: true))
        #expect(after.desktopProviders == ["SystemDefault": Self.livepaper])
        #expect(after.node(["SystemDefault"])?["Type"] as? String == "individual")
        #expect(StoreTree(after.entries("Idle")) == StoreTree(before.entries("Idle")))
    }

    @Test func `a second select writes nothing`() throws {
        try install(Fixture.spaces)
        try store.select(at: Self.selectedAt)
        let written = try Data(contentsOf: store.file)
        let kept = try Data(contentsOf: store.keptCopy)

        let edit = try store.select(at: Moment.after(120))

        #expect(edit == WallpaperStoreEdit(changed: 0, desktopEntries: 24))
        #expect(try Data(contentsOf: store.file) == written)
        #expect(try Data(contentsOf: store.keptCopy) == kept)
    }

    @Test func `a store that names Livepaper everywhere is not written, and nothing is kept`() throws {
        try install(Fixture.livepaper)

        let edit = try store.select(at: Self.selectedAt)

        #expect(edit == WallpaperStoreEdit(changed: 0, desktopEntries: 2))
        #expect(try Data(contentsOf: store.file) == Fixture.data(Fixture.livepaper))
        #expect(!keptCopyExists)
    }

    @Test func `a store half Livepaper keeps the copy from before`() throws {
        let original = try install(Fixture.aerial)
        try store.select(at: Self.selectedAt)
        let aerial = try #require(original.node(["SystemDefault", "Desktop"]))
        try install(onDisk().setting(aerial, at: ["SystemDefault", "Desktop"]).data())

        let edit = try store.select(at: Moment.after(120))

        #expect(edit == WallpaperStoreEdit(changed: 1, desktopEntries: 2, keptCopy: false))
        #expect(try StoreTree(contentsOf: store.keptCopy) == original)
    }

    @Test func `a store that names Livepaper nowhere is the user's own choice, and replaces an older copy`() throws {
        try install(Fixture.spaces)
        try store.select(at: Self.selectedAt)
        try install(Fixture.aerial)

        try store.select(at: Moment.after(120))

        #expect(try Data(contentsOf: store.keptCopy) == Fixture.data(Fixture.aerial))
    }

    // MARK: Leaving

    @Test(arguments: [Fixture.spaces, Fixture.aerial])
    func `deselect gives back the original, dates included`(fixture: String) throws {
        let original = try install(fixture)
        try store.select(at: Self.selectedAt)

        let edit = try store.deselect()

        let count = original.entries("Desktop").count
        #expect(edit == WallpaperStoreEdit(changed: count, desktopEntries: count))
        #expect(try onDisk() == original)
    }

    @Test func `an entry the user changed since select is left alone`() throws {
        let original = try install(Fixture.spaces)
        try store.select(at: Self.selectedAt)
        let space = try #require(original.node(["Spaces"])?.keys.sorted().first)
        let place = ["Spaces", space, "Default", "Desktop"]
        let theirs = try #require(original.node(["Displays"])?.values.first as? [String: Any])["Desktop"] as Any
        try install(onDisk().setting(theirs, at: place).data())

        let edit = try store.deselect()

        #expect(edit.changed == 23)
        #expect(try onDisk() == original.setting(theirs, at: place))
    }

    @Test func `a Space made since select goes back to the wallpaper for all Spaces, not the system default`() throws {
        let display = try #require(StoreTree(data: Fixture.data(Fixture.spaces)).node(["Displays"])?.values.first as? [String: Any])
        let still = display["Desktop"]
        let original = try StoreTree(data: Fixture.data(Fixture.aerial)).setting(still, at: ["AllSpacesAndDisplays", "Desktop"])
        try install(original.data())
        try store.select(at: Self.selectedAt)
        let livepaper = try #require(onDisk().node(["SystemDefault", "Desktop"]))
        let newSpace = ["Spaces", "0F0F0F0F-0000-4000-8000-00000000000A", "Default", "Desktop"]
        try install(onDisk().setting(livepaper, at: newSpace).data())

        try store.deselect()

        #expect(try onDisk() == original.setting(still, at: newSpace))
    }

    @Test func `leaving writes nothing when Livepaper is named nowhere`() throws {
        try install(Fixture.aerial)

        let edit = try store.deselect()

        #expect(edit == WallpaperStoreEdit(changed: 0, desktopEntries: 2))
        #expect(try Data(contentsOf: store.file) == Fixture.data(Fixture.aerial))
    }

    @Test func `leaving with no kept copy throws and writes nothing`() throws {
        try install(Fixture.livepaper)

        #expect(throws: WallpaperStoreError.noKeptCopy) { try store.deselect() }
        #expect(try Data(contentsOf: store.file) == Fixture.data(Fixture.livepaper))
    }

    @Test func `leaving with a copy that has nothing else to go back to throws and writes nothing`() throws {
        try install(Fixture.livepaper)
        try FileManager.default.createDirectory(at: store.keptCopy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Fixture.data(Fixture.livepaper).write(to: store.keptCopy)

        #expect(throws: WallpaperStoreError.nothingToGoBackTo) { try store.deselect() }
        #expect(try Data(contentsOf: store.file) == Fixture.data(Fixture.livepaper))
    }

    @Test func `leaving with a kept copy of a shape this build does not know throws`() throws {
        try install(Fixture.aerial)
        try store.select(at: Self.selectedAt)
        let selected = try Data(contentsOf: store.file)
        try Data("not a property list".utf8).write(to: store.keptCopy)

        #expect(throws: WallpaperStoreError.unknownShape(.keptCopy, .notADictionary)) { try store.deselect() }
        #expect(try Data(contentsOf: store.file) == selected)
    }

    @Test func `the kept copy goes when asked, after a leave`() throws {
        try install(Fixture.aerial)
        try store.select(at: Self.selectedAt)
        try store.deselect()

        store.removeKeptCopy()

        #expect(!keptCopyExists)
    }

    // MARK: Stores this build does not know

    @Test func `an unreadable store throws`() {
        #expect(throws: WallpaperStoreError.unreadable(.store)) { try store.select(at: Self.selectedAt) }
        #expect(throws: WallpaperStoreError.unreadable(.store)) { try store.deselect() }
        #expect(!keptCopyExists)
    }

    static func plist(_ value: Any) -> Data {
        (try? PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)) ?? Data()
    }

    static var aerialEntry: [String: Any] {
        ["Content": ["Choices": [["Provider": "com.apple.wallpaper.choice.aerials", "Files": [Any]()]], "Shuffle": "$null"]]
    }

    static let unknownShapes: [Row<Data, WallpaperStoreProblem>] = [
        Row("bytes that are not a property list", Data("<plist>".utf8), .notADictionary),
        Row("a property list that is a list", plist([aerialEntry]), .notADictionary),
        Row("a dictionary with none of the places", plist(["Wallpapers": ["Desktop": aerialEntry]]), .noPlaces),
        Row(
            "a place that is not a dictionary",
            plist(["SystemDefault": ["Desktop": aerialEntry], "Spaces": "none"]),
            .unexpected(at: "Spaces")
        ),
        Row(
            "a Desktop entry that is not a dictionary",
            plist(["SystemDefault": ["Desktop": "$null"], "Spaces": [String: Any]()]),
            .unexpected(at: "SystemDefault.Desktop")
        ),
        Row(
            "a Desktop entry with no choices",
            plist(["AllSpacesAndDisplays": ["Desktop": ["Content": ["Choices": [Any]()]]]]),
            .unexpected(at: "AllSpacesAndDisplays.Desktop")
        ),
        Row(
            "a choice with no provider, deep in a Space",
            plist(["Spaces": ["S1": ["Displays": ["D1": ["Desktop": ["Content": ["Choices": [["Files": [Any]()]]]]]]]]]),
            .unexpected(at: "Spaces.S1.Displays.D1.Desktop")
        ),
    ]

    @Test(arguments: unknownShapes)
    func `a store of a shape this build does not know throws, and nothing is written or kept`(
        row: Row<Data, WallpaperStoreProblem>
    ) throws {
        try install(row.input)

        #expect(throws: WallpaperStoreError.unknownShape(.store, row.expected)) { try store.select(at: Self.selectedAt) }
        #expect(throws: WallpaperStoreError.unknownShape(.store, row.expected)) { try store.deselect() }
        #expect(try Data(contentsOf: store.file) == row.input)
        #expect(!keptCopyExists)
    }

    // MARK: The shape check, for diagnostics

    @Test func `the shape check counts entries and says whether a copy is kept`() throws {
        try install(Fixture.spaces)
        let before = store.shape()
        try store.select(at: Self.selectedAt)

        let after = store.shape()

        #expect(before == WallpaperStoreShape(store: .read(desktopEntries: 24, namingLivepaper: 0), keptCopyExists: false))
        #expect(after == WallpaperStoreShape(store: .read(desktopEntries: 24, namingLivepaper: 24), keptCopyExists: true))
        #expect(after.description == "wallpaper store: 24 Desktop entries, 24 name Livepaper; kept copy: present")
    }

    @Test func `the shape check of a store chosen by hand`() throws {
        try install(Fixture.livepaper)

        #expect(store.shape() == WallpaperStoreShape(store: .read(desktopEntries: 2, namingLivepaper: 2), keptCopyExists: false))
    }

    @Test func `the shape check says unreadable, or an unknown shape, and names no file`() throws {
        let missing = store.shape()
        try install(Data("<plist>".utf8))

        let garbled = store.shape()

        #expect(missing.store == .unreadable)
        #expect(garbled.store == .unknownShape)
        #expect(missing.description == "wallpaper store: unreadable; kept copy: none")
        #expect(!garbled.description.contains("/"))
    }
}
