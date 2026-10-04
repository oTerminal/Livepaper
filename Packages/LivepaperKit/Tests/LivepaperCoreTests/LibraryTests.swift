import Foundation
import Testing
import LivepaperCore

struct LibraryTests {
    // MARK: Insert

    @Test func `insert puts the wallpaper in the library and returns a new value`() throws {
        let empty = Library()

        let library = try empty.inserting(.numbered(1))

        #expect(library.wallpapers == [.numbered(1)])
        #expect(library[.numbered(1)] == .numbered(1))
        #expect(empty.wallpapers.isEmpty)
    }

    @Test func `insert keeps the order of import`() throws {
        let library = try Library.of(.numbered(2), .numbered(1), .numbered(3))

        #expect(library.wallpapers.map(\.id) == [.numbered(2), .numbered(1), .numbered(3)])
    }

    @Test func `insert refuses an identifier that is already in the library`() throws {
        let library = try Library.of(.numbered(1))
        var other = Wallpaper.numbered(1, name: "Another file")
        other.fingerprint = Wallpaper.numbered(2).fingerprint

        #expect(throws: LibraryError.alreadyInLibrary(.numbered(1))) { try library.inserting(other) }
    }

    @Test func `insert refuses a source file that was already imported`() throws {
        let library = try Library.of(.numbered(1))
        var copy = Wallpaper.numbered(2, name: "The same file under another name")
        copy.fingerprint = Wallpaper.numbered(1).fingerprint

        #expect(throws: LibraryError.duplicate(of: .numbered(1))) { try library.inserting(copy) }
    }

    // MARK: Duplicate lookup

    @Test func `finds a wallpaper by the fingerprint of its source file`() throws {
        let library = try Library.of(.numbered(1), .numbered(2))
        let second = Wallpaper.numbered(2).fingerprint

        #expect(library.wallpaper(withFingerprint: second)?.id == .numbered(2))
        #expect(library.wallpaper(withFingerprint: Fingerprint(sha256: String(repeating: "f", count: 64))) == nil)
    }

    @Test func `fingerprints compare without regard to the case of their hex digits`() throws {
        var wallpaper = Wallpaper.numbered(1)
        wallpaper.fingerprint = Fingerprint(sha256: "ABCDEF" + String(repeating: "0", count: 58))
        let library = try Library.of(wallpaper)

        #expect(library.wallpaper(withFingerprint: Fingerprint(sha256: "abcdef" + String(repeating: "0", count: 58)))?.id == .numbered(1))
    }

    // MARK: Rename

    static let typedNames: [Row<String, String?>] = [
        Row("a name is kept", "Ocean at dusk", "Ocean at dusk"),
        Row("spaces and line breaks around it are dropped", " \tOcean \n", "Ocean"),
        Row("spaces inside it are kept", "Ocean  at dusk", "Ocean  at dusk"),
        Row("an empty name is none", "", nil),
        Row("a name of spaces and line breaks is none", " \n\t ", nil),
    ]

    @Test(arguments: typedNames)
    func `a typed name is the name kept, or none`(row: Row<String, String?>) {
        #expect(acceptedName(row.input) == row.expected)
    }

    static let renames: [Row<String, String?>] = [
        Row("a new name", "Ocean at dusk", "Ocean at dusk"),
        Row("spaces around the name are dropped", "  Ocean \n", "Ocean"),
        Row("an empty name is refused", "", nil),
        Row("a name of spaces is refused", "   ", nil),
    ]

    @Test(arguments: renames)
    func `renames a wallpaper`(row: Row<String, String?>) throws {
        let library = try Library.of(.numbered(1), .numbered(2))

        if let expected = row.expected {
            let renamed = try library.renaming(.numbered(2), to: row.input)
            #expect(renamed[.numbered(2)]?.name == expected)
            #expect(renamed[.numbered(1)] == .numbered(1))
            #expect(library[.numbered(2)]?.name == "Wallpaper 2")
        } else {
            #expect(throws: LibraryError.emptyName) { try library.renaming(.numbered(2), to: row.input) }
        }
    }

    // MARK: Favourite

    @Test func `marks and unmarks a favourite`() throws {
        let library = try Library.of(.numbered(1), .numbered(2))

        let marked = try library.settingFavourite(true, for: .numbered(2))
        let unmarked = try marked.settingFavourite(false, for: .numbered(2))

        #expect(marked.wallpapers.map(\.isFavourite) == [false, true])
        #expect(marked.favourites.map(\.id) == [.numbered(2)])
        #expect(library.favourites.isEmpty)
        #expect(unmarked == library)
    }

    // MARK: Presentation and volume

    @Test func `sets a wallpaper's presentation`() throws {
        let library = try Library.of(.numbered(1), .numbered(2))
        let framed = Presentation(fit: .fit, focalPoint: Point(x: 0.2, y: 0.8), zoom: 2, pan: Point(x: -0.1, y: 0.05))

        let changed = try library.settingPresentation(framed, for: .numbered(2))

        #expect(changed[.numbered(2)]?.presentation == framed)
        #expect(changed[.numbered(1)] == .numbered(1))
        #expect(library[.numbered(2)]?.presentation == Presentation())
    }

    static let volumes: [Row<Double, Double>] = [
        Row("a volume between silent and full", 0.35, 0.35),
        Row("silent", 0, 0),
        Row("full", 1, 1),
        Row("above full is full", 1.5, 1),
        Row("below silent is silent", -0.2, 0),
        Row("not a number is silent", .nan, 0),
        Row("infinity is silent", .infinity, 0),
    ]

    @Test(arguments: volumes)
    func `sets a wallpaper's volume, kept between silent and full`(row: Row<Double, Double>) throws {
        let library = try Library.of(.numbered(1))

        #expect(try library.settingVolume(row.input, for: .numbered(1))[.numbered(1)]?.volume == row.expected)
    }

    // MARK: Delete and restore

    @Test(arguments: [1, 2, 3])
    func `delete then restore is the identity`(number: Int) throws {
        let library = try Library.of(.numbered(1), .numbered(2, isFavourite: true), .numbered(3))

        let (without, removal) = try library.deleting(.numbered(number))
        let restored = try without.restoring(removal)

        #expect(without[.numbered(number)] == nil)
        #expect(without.wallpapers.count == 2)
        #expect(restored == library)
    }

    @Test func `delete then restore of the only wallpaper is the identity`() throws {
        let library = try Library.of(.numbered(1))

        let (without, removal) = try library.deleting(.numbered(1))

        #expect(without == Library())
        #expect(try without.restoring(removal) == library)
    }

    @Test func `a restore after the library has shrunk goes to the end`() throws {
        let library = try Library.of(.numbered(1), .numbered(2), .numbered(3))

        let (withoutThree, removal) = try library.deleting(.numbered(3))
        let (onlyOne, _) = try withoutThree.deleting(.numbered(2))
        let restored = try onlyOne.restoring(removal)

        #expect(restored.wallpapers.map(\.id) == [.numbered(1), .numbered(3)])
    }

    @Test func `a restore cannot bring back a wallpaper that is in the library`() throws {
        let library = try Library.of(.numbered(1))
        let (_, removal) = try library.deleting(.numbered(1))

        #expect(throws: LibraryError.alreadyInLibrary(.numbered(1))) { try library.restoring(removal) }
    }

    // MARK: Unknown wallpapers

    @Test func `changing a wallpaper that is not in the library is an error, not a silent no-op`() throws {
        let library = try Library.of(.numbered(1))
        let missing = LibraryError.noSuchWallpaper(.numbered(9))

        #expect(throws: missing) { try library.renaming(.numbered(9), to: "Ocean") }
        #expect(throws: missing) { try library.settingFavourite(true, for: .numbered(9)) }
        #expect(throws: missing) { try library.settingPresentation(Presentation(), for: .numbered(9)) }
        #expect(throws: missing) { try library.settingVolume(0.5, for: .numbered(9)) }
        #expect(throws: missing) { try library.deleting(.numbered(9)) }
    }

    // MARK: Sort

    static let sorts: [Row<Library.SortOrder, [Int]>] = [
        Row("newest first", .newestFirst, [4, 3, 2, 1]),
        Row("oldest first", .oldestFirst, [1, 2, 3, 4]),
        Row("by name: case and accents do not matter, and 2 comes before 10", .name, [3, 1, 4, 2]),
    ]

    @Test(arguments: sorts)
    func `sorts the library`(row: Row<Library.SortOrder, [Int]>) throws {
        let library = try Library.of(
            .numbered(2, name: "loop 10"),
            .numbered(4, name: "Loop 2"),
            .numbered(1, name: "éclair"),
            .numbered(3, name: "Aurora")
        )

        #expect(library.sorted(by: row.input).map(\.id) == row.expected.map(WallpaperID.numbered))
    }

    @Test func `wallpapers with the same name keep a fixed order`() throws {
        let library = try Library.of(.numbered(2, name: "Ocean"), .numbered(1, name: "ocean"), .numbered(3, name: "Océan"))

        #expect(library.sorted(by: .name).map(\.id) == [.numbered(1), .numbered(2), .numbered(3)])
    }

    // MARK: Search

    static let searches: [Row<String, [Int]>] = [
        Row("a word in a name", "ocean", [1, 4]),
        Row("case does not matter", "OCEAN", [1, 4]),
        Row("an unaccented query finds an accented name", "cafe", [2]),
        Row("an accented query finds an unaccented name", "ÔCÉAN", [1, 4]),
        Row("part of a word", "ngstr", [3]),
        Row("every word has to match, in any order", "dusk ocean", [1]),
        Row("spaces around the query are ignored", "  café  ", [2]),
        Row("an empty query finds everything", "", [1, 2, 3, 4]),
        Row("a query of spaces finds everything", "   ", [1, 2, 3, 4]),
        Row("no match finds nothing", "forest", []),
    ]

    @Test(arguments: searches)
    func `searches names`(row: Row<String, [Int]>) throws {
        let library = try Library.of(
            .numbered(1, name: "Ocean at Dusk"),
            .numbered(2, name: "Café Lights"),
            .numbered(3, name: "Ångström"),
            .numbered(4, name: "ocean, stormy")
        )

        #expect(library.search(row.input).map(\.id) == row.expected.map(WallpaperID.numbered))
    }

    @Test func `search results can be sorted`() throws {
        let library = try Library.of(.numbered(1, name: "Ocean B"), .numbered(2, name: "Forest"), .numbered(3, name: "ocean a"))

        #expect(library.search("ocean").sorted(by: .name).map(\.id) == [.numbered(3), .numbered(1)])
    }
}
