import Foundation
import Testing
import LivepaperCore

/// Every test gets its own folder under the temporary directory, removed afterwards.
final class LibraryStoreTests {
    let directory: URL
    let store: FileLibraryStore

    init() {
        directory = FileManager.default.temporaryDirectory
            .appending(path: "LivepaperCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        store = FileLibraryStore(manifest: directory.appending(path: "Livepaper/library.json"))
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    /// What `library-v1.0.json` says.
    static func fixtureLibrary() throws -> Library {
        try Library.of(
            Wallpaper(
                id: .numbered(1),
                name: "Ocean at Dusk",
                isFavourite: true,
                importedAt: Date(timeIntervalSince1970: 1_789_984_800.25),
                fingerprint: Fingerprint(sha256: "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"),
                optimisedCopy: .known("wallpapers/AAAAAAAA-0000-0000-0000-000000000001/wallpaper.mov"),
                poster: .known("wallpapers/AAAAAAAA-0000-0000-0000-000000000001/poster.heic"),
                hoverPreview: .known("wallpapers/AAAAAAAA-0000-0000-0000-000000000001/hover.mov"),
                details: WallpaperDetails(duration: 12.5, width: 3840, height: 2160, frameRate: 60, codec: "hevc", byteCount: 48_000_000),
                presentation: Presentation(fit: .fill, focalPoint: Point(x: 0.25, y: 0.5), zoom: 1.5, pan: Point(x: 0.1, y: -0.2)),
                volume: 0.4
            ),
            Wallpaper(
                id: .numbered(2),
                name: "Café Lights",
                importedAt: Date(timeIntervalSince1970: 1_789_985_100),
                fingerprint: Fingerprint(sha256: "60303ae22b998861bce3b28f33eec1be758a213c86c93c076dbe9f558c11c752"),
                optimisedCopy: .known("wallpapers/AAAAAAAA-0000-0000-0000-000000000002/wallpaper.mov"),
                poster: .known("wallpapers/AAAAAAAA-0000-0000-0000-000000000002/poster.heic"),
                details: WallpaperDetails(duration: 8, width: 1080, height: 1920, frameRate: 29.97, codec: "h264", byteCount: 9_500_000),
                presentation: Presentation(fit: .stretch)
            )
        )
    }

    /// The scene in `library-v1.1.json`.
    static let fixtureScene = Wallpaper(
        id: .numbered(3),
        name: "Lantern Street",
        importedAt: Date(timeIntervalSince1970: 1_789_985_400),
        fingerprint: Fingerprint(sha256: "2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae"),
        optimisedCopy: .known("wallpapers/AAAAAAAA-0000-0000-0000-000000000003/scene.pkg"),
        poster: .known("wallpapers/AAAAAAAA-0000-0000-0000-000000000003/poster.heic"),
        hoverPreview: .known("wallpapers/AAAAAAAA-0000-0000-0000-000000000003/hover.mov"),
        details: WallpaperDetails(duration: 0, width: 3840, height: 2160, frameRate: 30, codec: "scene", byteCount: 16_000_000),
        scene: WallpaperScene(project: .known("wallpapers/AAAAAAAA-0000-0000-0000-000000000003/project.json"), width: 3840, height: 2160)
    )

    private func damageManifest(_ damage: (Data) -> Data) throws {
        let data = try Data(contentsOf: store.manifest)
        try damage(data).write(to: store.manifest)
    }

    // MARK: Round trip

    @Test func `a saved library loads again`() throws {
        let library = try Library.of(.numbered(1), .numbered(2, name: "Café Lights", isFavourite: true))

        try store.save(library)

        #expect(try store.load() == library)
    }

    @Test func `a first launch, with no folder yet, loads an empty library`() throws {
        #expect(try store.load() == Library())
    }

    @Test func `each save replaces the one before`() throws {
        let one = try Library.of(.numbered(1))
        let two = try one.inserting(.numbered(2))

        try store.save(one)
        try store.save(two)

        #expect(try store.load() == two)
    }

    @Test func `a date from the real clock, with all its digits, loads exactly as it was saved`() throws {
        var wallpaper = Wallpaper.numbered(1)
        wallpaper = Wallpaper(
            id: wallpaper.id, name: wallpaper.name, importedAt: Date(timeIntervalSinceReferenceDate: 811_677_600.123_456_7),
            fingerprint: wallpaper.fingerprint, optimisedCopy: wallpaper.optimisedCopy, poster: wallpaper.poster,
            details: wallpaper.details
        )
        let library = try Library.of(wallpaper)

        try store.save(library)

        #expect(try store.load() == library)
    }

    @Test func `a manifest that names a file outside the library does not load`() throws {
        let json = try #require(String(bytes: try Library.of(.numbered(1)).encode(), encoding: .utf8))
            .replacing("wallpapers/\(WallpaperID.numbered(1))/poster.heic", with: "../../Keychains/login.keychain-db")
        #expect(json.contains("Keychains"))

        #expect(throws: LibraryPathError.illegalComponent("..")) { try Library.decode(Data(json.utf8)) }
    }

    // MARK: Migration

    @Test func `the version 1.0 fixture still loads`() throws {
        try FileManager.default.createDirectory(at: store.manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Fixture.data("library-v1.0").write(to: store.manifest)

        #expect(try store.load() == Self.fixtureLibrary())
    }

    @Test func `the version 1.1 fixture loads, with its scene`() throws {
        try FileManager.default.createDirectory(at: store.manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Fixture.data("library-v1.1").write(to: store.manifest)

        let library = try store.load()

        #expect(library.wallpapers.map(\.kind) == [.video, .scene])
        #expect(library[.numbered(1)] == (try Self.fixtureLibrary())[.numbered(1)])
        #expect(library[.numbered(3)] == Self.fixtureScene)
    }

    @Test func `a scene survives a round trip`() throws {
        let library = try Library.of(.numbered(1), Self.fixtureScene)

        try store.save(library)

        #expect(try store.load() == library)
    }

    /// A Livepaper that knows only 1.0 needs every field a 1.0 wallpaper has.
    /// It reads a scene as a video whose optimised copy is the package, which
    /// it cannot play, and so holds the poster.
    @Test func `a scene is written with everything a 1.0 reader needs, its package where the optimised copy was`() throws {
        let json = try #require(JSONSerialization.jsonObject(with: Library.of(Self.fixtureScene).encode()) as? [String: Any])
        let wallpaper = try #require((json["wallpapers"] as? [[String: Any]])?.first)

        let fieldsOfVersion1 = [
            "id", "name", "isFavourite", "importedAt", "fingerprint", "optimisedCopy", "poster", "details", "presentation", "volume",
        ]
        #expect(fieldsOfVersion1.allSatisfy { wallpaper[$0] != nil })
        #expect(wallpaper["optimisedCopy"] as? String == "wallpapers/\(WallpaperID.numbered(3))/scene.pkg")
    }

    @Test func `a video is written as it was before scenes, with no scene field`() throws {
        let json = try #require(JSONSerialization.jsonObject(with: Library.of(.numbered(1)).encode()) as? [String: Any])
        let wallpaper = try #require((json["wallpapers"] as? [[String: Any]])?.first)

        #expect(wallpaper["scene"] == nil)
        #expect(json["version"] as? [String: Int] == ["major": 1, "minor": 1])
    }

    @Test func `a newer minor version loads, and its new fields are ignored`() throws {
        let json = try #require(String(bytes: try Library.of(.numbered(1)).encode(), encoding: .utf8))
            .replacing(#""minor" : \#(Library.schemaVersion.minor)"#, with: #""minor" : 4"#)
            .replacing(#""volume" : 0"#, with: #""volume" : 0, "tags" : ["calm"]"#)
        #expect(json.contains(#""minor" : 4"#) && json.contains("tags"))

        #expect(try Library.decode(Data(json.utf8)) == Library.of(.numbered(1)))
    }

    @Test func `a manifest from an unknown major version is refused, and the older manifest is not used instead`() throws {
        try store.save(try Library.of(.numbered(1)))
        try store.save(try Library.of(.numbered(1), .numbered(2)))
        try damageManifest { _ in Data(#"{"version":{"major":2,"minor":0},"wallpapers":[]}"#.utf8) }

        #expect(throws: SchemaError.unsupportedVersion(SchemaVersion(major: 2, minor: 0))) { try self.store.load() }
    }

    // MARK: Damage (Wallper's "library emptied on restart")

    static let damage: [Row<@Sendable (Data) -> Data, Void>] = [
        Row("cut short halfway", { $0.prefix($0.count / 2) }, ()),
        Row("cut down to nothing", { _ in Data() }, ()),
        Row("overwritten with something that is not a manifest", { _ in Data("[]".utf8) }, ()),
    ]

    @Test(arguments: damage)
    func `a damaged manifest loads the last good one instead of an empty library`(row: Row<@Sendable (Data) -> Data, Void>) throws {
        let lastGood = try Library.of(.numbered(1))
        try store.save(lastGood)
        try store.save(try lastGood.inserting(.numbered(2)))

        try damageManifest(row.input)

        #expect(try store.load() == lastGood)
    }

    @Test func `a damaged manifest with nothing to fall back on is an error, never an empty library`() throws {
        try store.save(try Library.of(.numbered(1)))

        try damageManifest { $0.prefix($0.count / 2) }

        #expect(throws: (any Error).self) { try self.store.load() }
    }

    @Test func `a manifest that went missing loads the last good one`() throws {
        let lastGood = try Library.of(.numbered(1))
        try store.save(lastGood)
        try store.save(try lastGood.inserting(.numbered(2)))

        try FileManager.default.removeItem(at: store.manifest)

        #expect(try store.load() == lastGood)
    }

    @Test func `saving over a damaged manifest keeps the last good one`() throws {
        let lastGood = try Library.of(.numbered(1))
        let latest = try Library.of(.numbered(1), .numbered(3))
        try store.save(lastGood)
        try store.save(try lastGood.inserting(.numbered(2)))
        try damageManifest { $0.prefix($0.count / 2) }

        try store.save(latest)
        #expect(try store.load() == latest)

        try damageManifest { $0.prefix($0.count / 2) }
        #expect(try store.load() == lastGood)
    }

    @Test func `nothing is written outside the manifest's folder`() throws {
        try store.save(try Library.of(.numbered(1)))
        try store.save(try Library.of(.numbered(1), .numbered(2)))

        let written = try FileManager.default.subpathsOfDirectory(atPath: directory.path).sorted()

        #expect(written == ["Livepaper", "Livepaper/library.json", "Livepaper/library.previous.json"])
    }
}
