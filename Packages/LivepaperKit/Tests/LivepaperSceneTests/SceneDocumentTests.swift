import Foundation
import Testing
@testable import LivepaperScene
import LivepaperTestSupport

/// A scene's JSON read as it is drawn: its objects in order, each layer's
/// material and effects, particles and sounds, and its values with the item's
/// user properties at their defaults. On scenes made from nothing.
struct SceneDocumentTests {
    static let material = #"""
        {"passes": [{"shader": "genericimage2", "textures": ["plain"], "combos": {"version": 2}, "blending": "translucent"}]}
        """#

    /// A package with one layer, `layer`, over a 400 × 200 scene, and what it names.
    static func files(layers: [String], project: [String: Any] = [:], extra: [SyntheticScene.Entry] = []) throws -> SceneFiles {
        let entries = [
            SyntheticScene.Entry(
                "scene.json", json: SyntheticScene.sceneJSON(width: 400, height: 200, layers: layers, general: #""bloom": true"#)
            ),
            SyntheticScene.Entry("models/plain.json", json: #"{"material": "materials/plain.json"}"#),
            SyntheticScene.Entry("models/puppet.json", json: #"{"material": "materials/plain.json", "puppet": "models/puppet.mdl"}"#),
            SyntheticScene.Entry("materials/plain.json", json: material),
            SyntheticScene.Entry("materials/plain.tex", SyntheticScene.solidTexture(.init(200, 10, 10), width: 4, height: 4)),
        ] + extra
        return SceneFiles(package: try ScenePackage(data: SyntheticScene.package(entries)), project: project)
    }

    @Test func `reads a layer's place, size, colour and material`() throws {
        let layer = SyntheticScene.layer(
            model: "models/plain.json", origin: (100, 50), size: (80, 40),
            fields: [
                "id": "7", "name": #""sign""#, "scale": #""2 1 1""#, "angles": #""0 0 1.5""#, "alpha": "0.5", "color": #""1 0.5 0.25""#,
            ]
        )

        let document = try SceneDocument(files: Self.files(layers: [layer]))

        #expect(document.width == 400)
        #expect(document.height == 200)
        #expect(document.bool(document.general["bloom"], false))
        let read = try #require(document.layers.first)
        #expect(read.id == 7)
        #expect(read.name == "sign")
        #expect(read.kind == .image)
        #expect(read.transform.origin == SIMD3(100, 50, 0))
        #expect(read.transform.scale == SIMD3(2, 1, 1))
        #expect(read.transform.angles.z == 1.5)
        #expect(read.size == SIMD2(80, 40))
        #expect(read.alpha == 0.5)
        #expect(read.colour == SIMD3(1, 0.5, 0.25))
        #expect(read.material?.shader == "genericimage2")
        #expect(read.material?.textures == ["plain"])
        #expect(read.material?.combos == ["VERSION": 2])
        #expect(read.material?.blending == "translucent")
    }

    static let kinds: [Row<String, SceneLayer.Kind>] = [
        Row("a model with a material is an image", "models/plain.json", .image),
        Row(
            "Wallpaper Engine's fullscreen layer runs its effects over the picture so far", "models/util/fullscreenlayer.json",
            .fullscreen
        ),
        Row("its compose layer runs them over what is behind it", "models/util/composelayer.json", .compose),
        Row("its solid layer is a flat colour", "models/util/solidlayer.json", .solid),
    ]

    @Test(arguments: kinds)
    func `tells Wallpaper Engine's own layers from images`(row: Row<String, SceneLayer.Kind>) throws {
        let layer = SyntheticScene.layer(model: row.input, origin: (0, 0), size: (10, 10))

        let document = try SceneDocument(files: Self.files(layers: [layer]))

        #expect(document.layers.map(\.kind) == [row.expected])
    }

    @Test func `lines an effect's scene passes up with its material passes, skipping commands`() throws {
        let effect = """
            {"passes": [
              {"material": "materials/blur.json", "target": "_rt_half"},
              {"command": "copy", "source": "_rt_half", "target": "_rt_copy"},
              {"material": "materials/blur.json", "bind": [{"name": "previous", "index": 0}, {"name": "_rt_half", "index": 1}]}],
             "fbos": [{"name": "_rt_half", "scale": 2, "format": "rgba8888"}]}
            """
        let layer = SyntheticScene.layer(model: "models/plain.json", origin: (0, 0), size: (10, 10), fields: ["effects": """
            [{"file": "effects/blur/effect.json", "visible": false, "passes": [
              {"combos": {"vertical": 1}, "constantshadervalues": {"strength": 3}}, {"textures": [null, "masks/edge"]}]}]
            """])
        let files = try Self.files(layers: [layer], extra: [
            .init("effects/blur/effect.json", json: effect),
            .init(
                "materials/blur.json",
                json: #"{"passes": [{"shader": "effects/blur", "textures": [null, null], "combos": {"vertical": 0}}]}"#
            ),
        ])

        let read = try #require(SceneDocument(files: files).layers.first?.effects.first)

        #expect(read.name == "blur")
        #expect(!read.isVisible)
        #expect(read.targets.map(\.name) == ["_rt_half"])
        #expect(read.targets.map(\.scale) == [2])
        #expect(read.passes.map(\.command) == [nil, "copy", nil])
        #expect(read.passes[0].material?.combos == ["VERTICAL": 1])
        #expect(read.passes[0].material?.constants["strength"] as? Int == 3)
        #expect(read.passes[0].target == "_rt_half")
        #expect(read.passes[2].material?.combos == ["VERTICAL": 0])
        #expect(read.passes[2].material?.textures == [nil, "masks/edge"])
        #expect(read.passes[2].binds.map(\.name) == ["previous", "_rt_half"])
        #expect(read.passes[2].binds.map(\.slot) == [0, 1])
    }

    @Test func `reads particles and sounds, and keeps what it does not draw for the log`() throws {
        let objects = [
            #"{"id": 3, "name": "snow", "particle": "particles/snow.json", "origin": "10 20 0", "instanceoverride": {"count": 2}}"#,
            #"{"id": 4, "name": "rain", "sound": ["sounds/rain.mp3"], "volume": 0.5, "playbackmode": "loop"}"#,
            #"{"id": 5, "name": "clock", "text": {"value": "12:00"}}"#,
        ]

        let document = try SceneDocument(files: Self.files(layers: objects))

        guard case .particles(let particles) = document.objects[0], case .sound(let sound) = document.objects[1],
              case .other(let id, _, let keys) = document.objects[2] else {
            Issue.record("objects were \(document.objects)")
            return
        }
        #expect(particles.file == "particles/snow.json")
        #expect(particles.transform.origin == SIMD3(10, 20, 0))
        #expect(particles.overrides["count"] as? Int == 2)
        #expect(sound.files == ["sounds/rain.mp3"])
        #expect(sound.volume == 0.5)
        #expect(sound.playback == "loop")
        #expect(sound.isVisible)
        #expect(id == 5)
        #expect(keys.contains("text"))
    }

    @Test func `a layer whose model cannot be read is left out, and said so`() throws {
        let document = try SceneDocument(files: Self.files(layers: [
            SyntheticScene.layer(model: "models/missing.json", origin: (0, 0), size: (1, 1)),
            SyntheticScene.layer(model: "models/plain.json", origin: (0, 0), size: (1, 1)),
        ]))

        #expect(document.layers.count == 1)
        #expect(document.problems.count == 1)
    }

    // MARK: User properties

    static var project: [String: Any] { ["general": ["properties": [
        "rain": ["type": "bool", "value": false],
        "screen": ["type": "combo", "value": "3"],
        "tint": ["type": "color", "value": "0 1 0"],
    ]]] }

    static let bound: [Row<String, Bool>] = [
        Row("a value bound to a property takes the item's default, not the stored value", #"{"user": "rain", "value": true}"#, false),
        Row(
            "a condition on a combo holds when the default is that choice",
            #"{"user": {"name": "screen", "condition": "3"}, "value": false}"#,
            true
        ),
        Row("and fails otherwise", #"{"user": {"name": "screen", "condition": "1"}, "value": true}"#, false),
        Row("a value set by a script keeps its stored value", #"{"script": "export function update() {}", "value": false}"#, false),
        Row("a property the item does not declare keeps the stored value", #"{"user": "unknown", "value": true}"#, true),
    ]

    @Test(arguments: bound)
    func `reads user properties at the item's defaults`(row: Row<String, Bool>) throws {
        let layer = SyntheticScene.layer(model: "models/plain.json", origin: (0, 0), size: (1, 1), fields: ["visible": row.input])

        let document = try SceneDocument(files: Self.files(layers: [layer], project: Self.project))

        #expect(document.layers.first?.isVisible == row.expected)
    }

    @Test func `a shader constant bound to a colour property takes its default`() throws {
        let values = SceneValues(project: Self.project)

        #expect(values.vector(["user": "tint", "value": "1 1 1"], .zero) == SIMD3(0, 1, 0))
    }

    static let numbers: [Row<String, [Float]?>] = [
        Row("a number", "0.5", [0.5]),
        Row("a string of numbers", #""1 2.5 -3""#, [1, 2.5, -3]),
        Row("an array", "[4, 5]", [4, 5]),
        Row("a wrapped value", #"{"value": "6 7"}"#, [6, 7]),
        Row("null", "null", nil),
    ]

    @Test(arguments: numbers)
    func `reads numbers however they are written`(row: Row<String, [Float]?>) throws {
        let json = try JSONSerialization.jsonObject(with: Data("[\(row.input)]".utf8)) as? [Any]

        #expect(SceneValues().floats(json?.first) == row.expected)
    }
}
