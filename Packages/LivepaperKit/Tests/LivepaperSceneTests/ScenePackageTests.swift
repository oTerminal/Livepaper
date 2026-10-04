import Foundation
import Testing
import LivepaperCore
import LivepaperScene
import LivepaperTestSupport

struct ScenePackageTests {
    static let entries = [
        SyntheticScene.Entry("scene.json", json: #"{"objects": []}"#),
        SyntheticScene.Entry("materials/a.tex", Data([1, 2, 3])),
        SyntheticScene.Entry("empty.json", Data()),
    ]

    @Test func `gives each entry by name, and the names in the package's order`() throws {
        let package = try ScenePackage(data: SyntheticScene.package(Self.entries, version: "PKGV0021"))

        #expect(package.version == "PKGV0021")
        #expect(package.names == ["scene.json", "materials/a.tex", "empty.json"])
        #expect(package.entry("materials/a.tex") == Data([1, 2, 3]))
        #expect(package.entry("empty.json") == Data())
        #expect(package.entry("scene.json").flatMap { String(bytes: $0, encoding: .utf8) } == #"{"objects": []}"#)
    }

    @Test func `an entry it does not have is nil, or an error when it is required`() throws {
        let package = try ScenePackage(data: SyntheticScene.package(Self.entries))

        #expect(package.entry("gone.json") == nil)
        #expect(throws: SceneReadError.missingEntry("gone.json")) { try package.require("gone.json") }
    }

    static let damaged: [Row<Data, Void>] = [
        Row("nothing at all", Data(), ()),
        Row("another kind of file", Data("PNG and so on, not a package".utf8), ()),
        Row("cut short in its table", SyntheticScene.package(entries).prefix(30), ()),
        Row("cut short in its last entry", SyntheticScene.package(entries).dropLast(3), ()),
        Row("a count far larger than the file", {
            var data = SyntheticScene.package(entries)
            data.replaceSubrange(12..<16, with: [0xFF, 0xFF, 0xFF, 0x7F])
            return data
        }(), ()),
    ]

    @Test(arguments: damaged)
    func `a file that is not a whole package is refused, never read past its end`(row: Row<Data, Void>) {
        #expect(throws: SceneReadError.notAPackage) { try ScenePackage(data: row.input) }
    }

    @Test func `a package's scene is named after its project's file`() {
        #expect(SceneFolder.package(for: "scene.json") == "scene.pkg")
        #expect(SceneFolder.package(for: "gifscene.json") == "gifscene.pkg")
        #expect(SceneFolder.itemPackage(for: "night scene.json") == "night scene.pkg")
    }

    @Test func `in the library a package's name holds only what a library path can, and a name it could is kept`() throws {
        #expect(SceneFolder.package(for: "night scene.json") == "night_scene.pkg")
        #expect(SceneFolder.package(for: "夜.json") == "_.pkg")
        #expect(SceneFolder.package(for: "scenes/.main.json") == "scenes/_main.pkg")
        #expect(SceneFolder.package(for: "scene.v2.json") == "scene.v2.pkg")
        #expect(SceneFolder.package(for: "scenes/main.json") == "scenes/main.pkg")
        for name in ["night scene.json", "夜.json", "scenes/.main.json"] {
            _ = try LibraryPath("wallpapers/1/\(SceneFolder.package(for: name))")
        }
    }
}
