import Compression
import Foundation

/// Wallpaper Engine files made from nothing, for tests: tiny, and nobody's
/// work. Workshop items are other people's, and never go into this repository.
///
/// The layouts are the ones `LivepaperScene` reads (`ScenePackage`, `SpriteSheet`).
public enum SyntheticScene {
    /// One file inside a package.
    public struct Entry: Sendable {
        public var name: String
        public var data: Data

        public init(_ name: String, _ data: Data) {
            self.name = name
            self.data = data
        }

        public init(_ name: String, json: String) {
            self.init(name, Data(json.utf8))
        }
    }

    /// A picture of one colour, for a texture's image or a sprite-sheet frame.
    public struct Colour: Equatable, Sendable {
        public var red, green, blue: UInt8

        public init(_ red: UInt8, _ green: UInt8, _ blue: UInt8) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    /// One frame of a sprite sheet: which image, how long, where.
    public struct Frame: Sendable {
        public var image: Int
        public var seconds: Float
        public var x, y, width, height: Float

        public init(image: Int, seconds: Float, x: Float, y: Float, width: Float, height: Float) {
            self.image = image
            self.seconds = seconds
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }
    }

    // MARK: Packages

    /// A `.pkg` holding `entries` in their order.
    public static func package(_ entries: [Entry], version: String = "PKGV0018") -> Data {
        var table = Data()
        var body = Data()
        for entry in entries {
            table.append(string: entry.name)
            table.append(u32: UInt32(body.count))
            table.append(u32: UInt32(entry.data.count))
            body.append(entry.data)
        }
        var data = Data()
        data.append(string: version)
        data.append(u32: UInt32(entries.count))
        return data + table + body
    }

    // MARK: Textures

    /// A `.tex` whose images are laid out side by side as tiles of `tile` pixels,
    /// one tile per colour, and whose sprite sheet is those tiles in order, each
    /// shown for `seconds`. `perImage` tiles go in each image, so more than that
    /// spreads the sheet over several images, as a long GIF is.
    public static func spriteSheet(
        _ colours: [Colour], tile: (width: Int, height: Int), perImage: Int = 4, seconds: Float = 0.1, compressed: Bool = true
    ) -> Data {
        let groups = stride(from: 0, to: colours.count, by: perImage).map { Array(colours[$0..<min($0 + perImage, colours.count)]) }
        let images = groups.map { group in
            RawImage(width: tile.width * group.count, height: tile.height, pixels: tiles(group, tile: tile))
        }
        var frames: [Frame] = []
        for (index, group) in groups.enumerated() {
            for position in group.indices {
                let x = Float(position * tile.width)
                frames.append(Frame(image: index, seconds: seconds, x: x, y: 0, width: Float(tile.width), height: Float(tile.height)))
            }
        }
        return texture(images, frames: frames, compressed: compressed)
    }

    /// An image's pixels, RGBA8888, before any compression.
    public struct RawImage: Sendable {
        public var width: Int
        public var height: Int
        public var pixels: Data

        public init(width: Int, height: Int, pixels: Data) {
            self.width = width
            self.height = height
            self.pixels = pixels
        }
    }

    /// A `.tex` of raw RGBA8888 images ("TEXB0003", one mip each), with a
    /// sprite sheet ("TEXS0003") when `frames` is not nil.
    public static func texture(_ images: [RawImage], frames: [Frame]?, compressed: Bool = true, format: Int32 = 0) -> Data {
        var data = Data()
        data.append(tag: "TEXV0005")
        data.append(tag: "TEXI0001")
        for value in [format, 4, Int32(images.first?.width ?? 0), Int32(images.first?.height ?? 0)] { data.append(i32: value) }
        for value in [Int32(images.first?.width ?? 0), Int32(images.first?.height ?? 0), 0] { data.append(i32: value) }
        data.append(tag: "TEXB0003")
        data.append(i32: Int32(images.count))
        data.append(i32: -1)
        for image in images {
            // The system's encoder declines very small inputs; those are stored as they are, as Wallpaper Engine may too.
            let packed = compressed ? lz4(image.pixels) : Data()
            let isPacked = !packed.isEmpty
            let payload = isPacked ? packed : image.pixels
            data.append(i32: 1)
            for value in [image.width, image.height, isPacked ? 1 : 0, isPacked ? image.pixels.count : 0, payload.count] {
                data.append(i32: Int32(value))
            }
            data.append(payload)
        }
        guard let frames else { return data }
        data.append(tag: "TEXS0003")
        data.append(i32: Int32(frames.count))
        data.append(i32: Int32(frames.first?.width ?? 0))
        data.append(i32: Int32(frames.first?.height ?? 0))
        for frame in frames {
            data.append(i32: Int32(frame.image))
            for value in [frame.seconds, frame.x, frame.y, frame.width, 0, 0, frame.height] { data.append(f32: value) }
        }
        return data
    }

    // MARK: Scenes

    /// A GIF scene's own files, as Wallpaper Engine's GIF template writes them:
    /// one image layer over the whole scene, its model, its material, and its texture.
    public static func gifScene(width: Int, height: Int, texture: Data, sceneFile: String = "gifscene.json") -> [Entry] {
        [
            Entry(sceneFile, json: sceneJSON(width: width, height: height, layers: [imageLayer(width: width, height: height)])),
            Entry("models/background.json", json: #"{"material": "materials/background.json", "autosize": true}"#),
            Entry("materials/background.json", json: """
                {"passes": [{"shader": "genericimage", "textures": ["background"], "combos": {"spritesheet": 1}}]}
                """),
            Entry("materials/background.tex", texture),
        ]
    }

    /// A scene's JSON: its size, and its layers as JSON objects.
    public static func sceneJSON(width: Int, height: Int, layers: [String], general: String = "") -> String {
        let projection = #""orthogonalprojection": {"width": \#(width), "height": \#(height)}"#
        let settings = general.isEmpty ? projection : "\(projection), \(general)"
        let objects = layers.joined(separator: ", ")
        return #"{"camera": {}, "general": {"clearcolor": "0 0 0", \#(settings)}, "objects": [\#(objects)], "version": 0}"#
    }

    /// An image layer over the whole scene, as the GIF template makes it. Each
    /// of `fields` replaces or adds one field: its name, and its value as JSON.
    public static func imageLayer(width: Int, height: Int, fields: [String: String] = [:]) -> String {
        let plain = [
            "image": #""models/background.json""#,
            "origin": #""\#(Double(width) / 2) \#(Double(height) / 2) 0""#,
            "size": #""\#(width) \#(height)""#,
            "scale": #""1 1 1""#,
            "angles": #""0 0 0""#,
            "alpha": "1.0",
            "visible": "true",
        ]
        let merged = plain.merging(fields) { _, new in new }
        return "{" + merged.keys.sorted().map { "\"\($0)\": \(merged[$0] ?? "null")" }.joined(separator: ", ") + "}"
    }

    /// A scene drawn with two programs: an image layer whose material's shader
    /// is `genericimage2`, which the package does not carry, and an effect on it,
    /// `effects/tint`, whose two stages it does, in Wallpaper Engine's GLSL
    /// dialect. `fragment` replaces the effect's fragment stage.
    public static func sceneWithEffect(width: Int = 1920, height: Int = 1080, fragment: String = tintFragment) -> [Entry] {
        let layer = imageLayer(width: width, height: height, fields: ["effects": #"[{"file": "effects/tint/effect.json"}]"#])
        return [
            Entry("scene.json", json: sceneJSON(width: width, height: height, layers: [layer])),
            Entry("models/background.json", json: #"{"material": "materials/background.json"}"#),
            Entry("materials/background.json", json: #"{"passes": [{"shader": "genericimage2", "textures": ["background"]}]}"#),
            Entry("materials/background.tex", Data("TEXV0005".utf8)),
            Entry("effects/tint/effect.json", json: #"{"name": "tint", "passes": [{"material": "materials/effects/tint.json"}]}"#),
            Entry("materials/effects/tint.json", json: #"{"passes": [{"shader": "effects/tint", "combos": {"soft": 1}}]}"#),
            Entry("shaders/effects/tint.vert", Data(tintVertex.utf8)),
            Entry("shaders/effects/tint.frag", Data(fragment.utf8)),
        ]
    }

    /// The tint effect's vertex stage: a combo, loose uniforms, attributes and a varying.
    public static let tintVertex = """
        // [COMBO] {"material":"Soft edges","combo":"SOFT","type":"options","default":0}

        uniform mat4 g_ModelViewProjectionMatrix;

        attribute vec3 a_Position;
        attribute vec2 a_TexCoord;

        varying vec2 v_TexCoord;

        void main() {
            gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
            v_TexCoord = a_TexCoord;
        }
        """

    /// The tint effect's fragment stage: a texture, and uniforms with their material keys and defaults.
    public static let tintFragment = """
        #include "common.h"

        uniform sampler2D g_Texture0; // {"hidden":true}
        uniform vec3 g_TintColour; // {"material":"colour","default":"1 0.5 0.25"}
        uniform float g_Strength; // {"material":"strength","default":0.5}

        varying vec2 v_TexCoord;

        void main() {
            vec4 albedo = texSample2D(g_Texture0, v_TexCoord);
        #if SOFT
            albedo.a = smoothstep(0.0, 1.0, albedo.a);
        #endif
            gl_FragColor = vec4(lerp(albedo.rgb, albedo.rgb * g_TintColour, saturate(g_Strength)), albedo.a);
        }
        """

    // MARK: Helpers

    private static func tiles(_ colours: [Colour], tile: (width: Int, height: Int)) -> Data {
        var pixels = Data(capacity: colours.count * tile.width * tile.height * 4)
        for _ in 0..<tile.height {
            for colour in colours {
                for _ in 0..<tile.width { pixels.append(contentsOf: [colour.red, colour.green, colour.blue, 255]) }
            }
        }
        return pixels
    }

    private static func lz4(_ data: Data) -> Data {
        var output = Data(count: data.count + data.count / 255 + 64)
        let size = output.count
        let written = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source -> Int in
                guard let to = destination.baseAddress, let from = source.baseAddress else { return 0 }
                return compression_encode_buffer(
                    to.assumingMemoryBound(to: UInt8.self), size,
                    from.assumingMemoryBound(to: UInt8.self), data.count,
                    nil, COMPRESSION_LZ4_RAW
                )
            }
        }
        return output.prefix(written)
    }
}

extension Data {
    fileprivate mutating func append(u32 value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    fileprivate mutating func append(i32 value: Int32) {
        append(u32: UInt32(bitPattern: value))
    }

    fileprivate mutating func append(f32 value: Float) {
        append(u32: value.bitPattern)
    }

    fileprivate mutating func append(string: String) {
        append(u32: UInt32(string.utf8.count))
        append(contentsOf: Array(string.utf8))
    }

    fileprivate mutating func append(tag: String) {
        append(contentsOf: Array(tag.utf8) + [0])
    }
}
