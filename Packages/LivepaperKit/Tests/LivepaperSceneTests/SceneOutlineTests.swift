import Foundation
import Testing
import LivepaperCore
import LivepaperScene
import LivepaperTestSupport

struct SceneOutlineTests {
    typealias Entry = SyntheticScene.Entry
    typealias Change = @Sendable (inout [Entry]) -> Void

    static let texture = SyntheticScene.spriteSheet(
        [SyntheticScene.Colour(255, 0, 0), SyntheticScene.Colour(0, 255, 0)], tile: (4, 2)
    )

    /// A GIF scene of 1920 by 1080, with `change` made to its files first.
    static func gifScene(_ change: Change = { _ in }) -> [Entry] {
        var entries = SyntheticScene.gifScene(width: 1920, height: 1080, texture: texture, sceneFile: "scene.json")
        change(&entries)
        return entries
    }

    /// The scene's JSON: its one image layer with `fields` changed, other `layers` after it, and `general` settings.
    static func scene(layer fields: [String: String] = [:], general: String = "", layers more: [String] = []) -> Change {
        { entries in
            let layers = [SyntheticScene.imageLayer(width: 1920, height: 1080, fields: fields)] + more
            entries[0] = Entry("scene.json", json: SyntheticScene.sceneJSON(width: 1920, height: 1080, layers: layers, general: general))
        }
    }

    static func replacing(_ name: String, with json: String) -> Change {
        { entries in
            guard let index = entries.firstIndex(where: { $0.name == name }) else { return }
            entries[index] = Entry(name, json: json)
        }
    }

    static func outline(_ entries: [Entry]) throws -> SceneOutline {
        try readSceneOutline(of: "scene.json", in: ScenePackage(data: SyntheticScene.package(entries)))
    }

    // MARK: Size

    @Test func `the size is the orthogonal projection's`() throws {
        #expect(try Self.outline(Self.gifScene()).size == Size(width: 1920, height: 1080))
    }

    static let sizes: [Row<String, Size?>] = [
        Row("whole numbers", #""orthogonalprojection": {"width": 3840, "height": 2160}"#, Size(width: 3840, height: 2160)),
        Row(
            "numbers with a fraction, rounded",
            #""orthogonalprojection": {"width": 1919.6, "height": 1080.2}"#,
            Size(width: 1920, height: 1080)
        ),
        Row("one that sizes itself to the display", #""orthogonalprojection": {"auto": true}"#, nil),
        Row("none: a scene in perspective", #""fov": 50"#, nil),
        Row("nothing across", #""orthogonalprojection": {"width": 0, "height": 1080}"#, nil),
    ]

    @Test(arguments: sizes)
    func `a scene's size comes from its orthogonal projection, or there is none`(row: Row<String, Size?>) throws {
        let json = #"{"general": {\#(row.input)}, "objects": []}"#

        #expect(try Self.outline([Entry("scene.json", json: json)]).size == row.expected)
    }

    @Test func `the clear colour is read, and black when there is none`() throws {
        let json = #"{"general": {"clearcolor": "0.70000 0.50000 0.25000"}, "objects": []}"#

        #expect(try Self.outline([Entry("scene.json", json: json)]).clearColour == [0.7, 0.5, 0.25])
        #expect(try Self.outline([Entry("scene.json", json: #"{"objects": []}"#)]).clearColour == [0, 0, 0])
    }

    @Test func `a scene whose JSON cannot be read, or is not there, is an error`() throws {
        #expect(throws: SceneReadError.malformedScene) { try Self.outline([Entry("scene.json", json: "{ not json")]) }
        #expect(throws: SceneReadError.missingEntry("scene.json")) { try Self.outline([Entry("other.json", json: "{}")]) }
    }

    @Test func `a byte-order mark before the JSON is no obstacle`() throws {
        let json = Data([0xEF, 0xBB, 0xBF]) + Data(#"{"general": {"orthogonalprojection": {"width": 8, "height": 6}}}"#.utf8)

        #expect(try Self.outline([Entry("scene.json", json)]).size == Size(width: 8, height: 6))
    }

    // MARK: The GIF-scene rule

    @Test func `a GIF scene names the texture that is the whole scene`() throws {
        #expect(try Self.outline(Self.gifScene()).spriteSheet == "materials/background.tex")
    }

    static let genericImage = #"{"shader": "genericimage", "textures": ["background"]}"#

    static let notGIFScenes: [Row<Change, Void>] = [
        Row("an effect on the layer", scene(layer: ["effects": #"[{"file": "effects/waterripple/effect.json"}]"#]), ()),
        Row("particles beside it", scene(layers: [#"{"particle": "particles/rain.json"}"#]), ()),
        Row("a second image layer", scene(layers: [SyntheticScene.imageLayer(width: 1920, height: 1080)]), ()),
        Row("a sound layer beside it", scene(layers: [#"{"sound": ["sounds/rain.mp3"]}"#]), ()),
        Row("a layer smaller than the scene", scene(layer: ["size": #""960 540""#]), ()),
        Row("a layer off centre", scene(layer: ["origin": #""100 540 0""#]), ()),
        Row("a layer scaled", scene(layer: ["scale": #""1.5 1.5 1""#]), ()),
        Row("a layer turned", scene(layer: ["angles": #""0 0 12""#]), ()),
        Row("a layer tinted", scene(layer: ["color": #""1 0.5 0.5""#]), ()),
        Row("a layer half transparent", scene(layer: ["alpha": "0.5"]), ()),
        Row("a layer's alpha bound to a user property", scene(layer: ["alpha": #"{"user": "opacity", "value": 1}"#]), ()),
        Row("a layer a user property shows or hides", scene(layer: ["visible": #"{"user": "rain", "value": true}"#]), ()),
        Row("a hidden layer", scene(layer: ["visible": "false"]), ()),
        Row("bloom over the whole scene", scene(general: #""bloom": true"#), ()),
        Row("a camera that shakes", scene(general: #""camerashake": true"#), ()),
        Row(
            "a puppet model",
            replacing("models/background.json", with: #"{"material": "materials/background.json", "puppet": "p.mdl"}"#),
            ()
        ),
        Row(
            "a shader of its own",
            replacing("materials/background.json", with: #"{"passes": [{"shader": "custom", "textures": ["background"]}]}"#),
            ()
        ),
        Row("two passes", replacing("materials/background.json", with: #"{"passes": [\#(genericImage), \#(genericImage)]}"#), ()),
        Row(
            "two textures",
            replacing("materials/background.json", with: #"{"passes": [{"shader": "genericimage", "textures": ["background", "mask"]}]}"#),
            ()
        ),
        Row("a texture that is not in the package", { $0.removeLast() }, ()),
        Row("a model that is not in the package", { $0.remove(at: 1) }, ()),
    ]

    @Test(arguments: notGIFScenes)
    func `anything more than one plain image over the whole scene is not a GIF scene`(row: Row<Change, Void>) throws {
        let outline = try Self.outline(Self.gifScene(row.input))

        #expect(outline.spriteSheet == nil)
        #expect(outline.size == Size(width: 1920, height: 1080))
    }

    @Test func `a scene with no size is no GIF scene either`() throws {
        let entries = Self.gifScene(Self.replacing("scene.json", with: #"{"general": {}, "objects": []}"#))

        #expect(try Self.outline(entries) == SceneOutline(size: nil, spriteSheet: nil))
    }
}
