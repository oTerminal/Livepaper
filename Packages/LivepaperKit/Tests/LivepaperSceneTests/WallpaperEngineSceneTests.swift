import Foundation
import Metal
import Testing
@testable import LivepaperScene
import LivepaperTestSupport

/// Drawing a scene offscreen, as the extension's scene engine drives it, and
/// reading back the pixels: layers where the scene puts them, over its clear
/// colour, in its order, a sprite sheet's frame by the time, a puppet posed.
/// The programs are written by hand in Metal as the translation would write
/// them (`SyntheticScene.imageProgramsJSON`), so these need a GPU and no tools.
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil))
final class WallpaperEngineSceneTests {
    let folder = FileManager.default.temporaryDirectory.appending(path: "livepaper-scene-\(UUID().uuidString)", directoryHint: .isDirectory)
    let device = MTLCreateSystemDefaultDevice()!

    deinit {
        try? FileManager.default.removeItem(at: folder)
    }

    static let red = SyntheticScene.Colour(255, 0, 0)
    static let blue = SyntheticScene.Colour(0, 0, 255)

    /// A material of one translucent `genericimage2` pass drawing the texture `texture`.
    static func material(texture: String) -> String {
        #"{"passes": [{"shader": "genericimage2", "textures": ["\#(texture)"], "blending": "translucent"}]}"#
    }

    /// A 64 × 32 scene over a grey clear colour, of the layers given, each drawn from `material`.
    func scene(layers: [String], extra: [SyntheticScene.Entry] = [], programs: String? = SyntheticScene.imageProgramsJSON) throws -> URL {
        let entries = [
            SyntheticScene.Entry("scene.json", json: #"""
                {"general": {"clearcolor": "0.5 0.5 0.5", "orthogonalprojection": {"width": 64, "height": 32}},
                 "objects": [\#(layers.joined(separator: ", "))]}
                """#),
            SyntheticScene.Entry("models/red.json", json: #"{"material": "materials/red.json"}"#),
            SyntheticScene.Entry("models/blue.json", json: #"{"material": "materials/blue.json"}"#),
            SyntheticScene.Entry("materials/red.json", json: Self.material(texture: "red")),
            SyntheticScene.Entry("materials/blue.json", json: Self.material(texture: "blue")),
            SyntheticScene.Entry("materials/red.tex", SyntheticScene.solidTexture(Self.red, width: 4, height: 4)),
            SyntheticScene.Entry("materials/blue.tex", SyntheticScene.solidTexture(Self.blue, width: 4, height: 4)),
        ] + extra
        try SyntheticScene.writeFolder(at: folder, entries: entries, programs: programs)
        return folder
    }

    /// The picture at `time`, drawn at `width` × `height`, as BGRA bytes.
    func draw(_ scene: WallpaperEngineScene, width: Int = 64, height: Int = 32, at time: Double = 0) throws -> [UInt8] {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: SceneFolder.pixelFormat, width: width, height: height, mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let target = try #require(device.makeTexture(descriptor: descriptor))
        let queue = try #require(device.makeCommandQueue())
        let buffer = try #require(queue.makeCommandBuffer())
        scene.resize(width: width, height: height)
        scene.draw(into: target, on: buffer, at: time)
        buffer.commit()
        buffer.waitUntilCompleted()
        #expect(buffer.error == nil)
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        target.getBytes(&pixels, bytesPerRow: width * 4, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return pixels
    }

    /// Red, green and blue at a pixel, from the top left.
    func colour(_ pixels: [UInt8], x: Int, y: Int, width: Int = 64) -> [UInt8] {
        let index = (y * width + x) * 4
        return [pixels[index + 2], pixels[index + 1], pixels[index]]
    }

    @Test func `draws a layer where the scene puts it, over the scene's clear colour`() throws {
        // The left half of the scene: y runs up from the bottom, as in Wallpaper Engine.
        let folder = try scene(layers: [SyntheticScene.layer(model: "models/red.json", origin: (16, 16), size: (32, 32))])

        let pixels = try draw(WallpaperEngineScene(folder: folder, device: device))

        #expect(colour(pixels, x: 8, y: 16) == [255, 0, 0])
        #expect(colour(pixels, x: 56, y: 16).allSatisfy { abs(Int($0) - 128) <= 2 })
    }

    @Test func `draws the scene's objects in order, later over earlier`() throws {
        let folder = try scene(layers: [
            SyntheticScene.layer(model: "models/red.json", origin: (32, 16), size: (64, 32)),
            SyntheticScene.layer(model: "models/blue.json", origin: (48, 16), size: (32, 32)),
        ])

        let pixels = try draw(WallpaperEngineScene(folder: folder, device: device))

        #expect(colour(pixels, x: 8, y: 16) == [255, 0, 0])
        #expect(colour(pixels, x: 56, y: 16) == [0, 0, 255])
    }

    @Test func `leaves out a layer that is not visible, and fades one by its alpha`() throws {
        let folder = try scene(layers: [
            SyntheticScene.layer(model: "models/red.json", origin: (16, 16), size: (32, 32), fields: ["visible": "false"]),
            SyntheticScene.layer(model: "models/blue.json", origin: (48, 16), size: (32, 32), fields: ["alpha": "0.5"]),
        ])

        let pixels = try draw(WallpaperEngineScene(folder: folder, device: device))

        #expect(colour(pixels, x: 8, y: 16).allSatisfy { abs(Int($0) - 128) <= 2 })
        let faded = colour(pixels, x: 56, y: 16)
        #expect(abs(Int(faded[0]) - 64) <= 3 && abs(Int(faded[2]) - 191) <= 3)
    }

    @Test func `covers an output of another shape, centred, cropping the longer way`() throws {
        // A 2:1 scene into a square: the middle square of it, so the red left quarter goes and the
        // blue second quarter is the left half of the picture, at the scene's own scale.
        let folder = try scene(layers: [
            SyntheticScene.layer(model: "models/red.json", origin: (8, 16), size: (16, 32)),
            SyntheticScene.layer(model: "models/blue.json", origin: (24, 16), size: (16, 32)),
        ])

        let pixels = try draw(WallpaperEngineScene(folder: folder, device: device), width: 32, height: 32)

        #expect(colour(pixels, x: 1, y: 16, width: 32) == [0, 0, 255])
        #expect(colour(pixels, x: 14, y: 16, width: 32) == [0, 0, 255])
        #expect(colour(pixels, x: 18, y: 16, width: 32).allSatisfy { abs(Int($0) - 128) <= 2 })
    }

    @Test func `shows a sprite sheet's frame by the time`() throws {
        let sheet = SyntheticScene.spriteSheet([Self.red, Self.blue], tile: (4, 4), perImage: 2, seconds: 0.5, compressed: false)
        let folder = try scene(
            layers: [SyntheticScene.layer(model: "models/sheet.json", origin: (32, 16), size: (64, 32))],
            extra: [
                .init("models/sheet.json", json: #"{"material": "materials/sheet.json"}"#),
                .init("materials/sheet.json", json: #"{"passes": [{"shader": "genericimage2", "textures": ["sheet"]}]}"#),
                .init("materials/sheet.tex", sheet),
            ]
        )
        let drawing = try WallpaperEngineScene(folder: folder, device: device)

        #expect(colour(try draw(drawing, at: 0.25), x: 32, y: 16) == [255, 0, 0])
        #expect(colour(try draw(drawing, at: 0.75), x: 32, y: 16) == [0, 0, 255])
        #expect(colour(try draw(drawing, at: 1.25), x: 32, y: 16) == [255, 0, 0])
    }

    @Test func `draws the same picture for the same time, however it got there`() throws {
        // Particles are simulated from what came before, so going on to 7 s and back to 3 must start again.
        let folder = try scene(
            layers: [#"{"id": 5, "name": "motes", "particle": "particles/motes.json", "origin": "32 16 0"}"#],
            extra: [
                .init("particles/motes.json", json: #"""
                    {"material": "materials/mote.json", "maxcount": 40,
                     "emitter": [{"name": "boxrandom", "rate": 8, "distancemax": "24 10 0"}],
                     "initializer": [{"name": "lifetimerandom", "min": 2, "max": 2}, {"name": "sizerandom", "min": 4, "max": 4},
                                     {"name": "velocityrandom", "min": "-6 -3 0", "max": "6 3 0"}],
                     "operator": [{"name": "movement"}]}
                    """#),
                .init("materials/mote.json", json: #"{"passes": [{"shader": "genericparticle", "textures": ["red"]}]}"#),
            ],
            programs: Self.particleProgramsJSON
        )
        let drawing = try WallpaperEngineScene(folder: folder, device: device)

        let first = try draw(drawing, at: 3)
        let later = try draw(drawing, at: 7)

        let reds = (0..<32).flatMap { y in (0..<64).map { x in colour(first, x: x, y: y) } }.filter { $0 == [255, 0, 0] }
        #expect(reds.count > 50, "the particles are drawn")
        #expect(later != first, "the particles move")
        #expect(try draw(drawing, at: 3) == first)
    }

    /// `scene-programs.json` with the one program particles are drawn with here:
    /// the texture times each particle's colour, written in Metal as the translation would.
    static let particleProgramsJSON = """
        {"translator": 1, "tools": "written by hand",
         "programs": {"genericparticle|": {"shader": "genericparticle", "defines": {}, "origin": "builtin",
           "uniforms": {}, "samplerDefaults": {},
           "program": {
             "vertex": {"entryPoint": "main0", "msl": \(jsonString(particleVertex)),
               "uniforms": {"size": 64, "members": [{"name": "g_ModelViewProjectionMatrix", "type": "mat4", "offset": 0, "stride": 64}]},
               "samplers": {}, "varyings": [{"name": "v_TexCoord", "type": "vec2"}, {"name": "v_Color", "type": "vec4"}],
               "attributes": [{"name": "a_Position", "type": "vec3", "location": 0}, {"name": "a_TexCoord", "type": "vec2", "location": 1},
                              {"name": "a_Color", "type": "vec4", "location": 2}]},
             "fragment": {"entryPoint": "main0", "msl": \(jsonString(particleFragment)),
               "uniforms": {"size": 16, "members": []},
               "samplers": {"g_Texture0": 0}, "varyings": [{"name": "v_TexCoord", "type": "vec2"}, {"name": "v_Color", "type": "vec4"}],
               "attributes": []}}}},
         "requests": {"genericparticle||0": "genericparticle|"},
         "failures": {}}
        """

    private static let particleVertex = """
        #include <metal_stdlib>
        using namespace metal;
        struct Uniforms { float4x4 g_ModelViewProjectionMatrix; };
        struct In { float3 a_Position [[attribute(0)]]; float2 a_TexCoord [[attribute(1)]]; float4 a_Color [[attribute(2)]]; };
        struct Out { float4 position [[position]]; float2 v_TexCoord [[user(locn0)]]; float4 v_Color [[user(locn1)]]; };
        vertex Out main0(In in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
            Out out;
            out.position = u.g_ModelViewProjectionMatrix * float4(in.a_Position, 1.0);
            out.v_TexCoord = in.a_TexCoord;
            out.v_Color = in.a_Color;
            return out;
        }
        """

    private static let particleFragment = """
        #include <metal_stdlib>
        using namespace metal;
        struct In { float2 v_TexCoord [[user(locn0)]]; float4 v_Color [[user(locn1)]]; };
        fragment float4 main0(In in [[stage_in]], texture2d<float> g_Texture0 [[texture(0)]], sampler g_Texture0Smplr [[sampler(0)]]) {
            return g_Texture0.sample(g_Texture0Smplr, in.v_TexCoord) * in.v_Color;
        }
        """

    private static func jsonString(_ text: String) -> String {
        let empty = #"[""]"#
        let data = (try? JSONSerialization.data(withJSONObject: [text])) ?? Data(empty.utf8)
        return String((String(bytes: data, encoding: .utf8) ?? empty).dropFirst().dropLast())
    }

    @Test func `cannot load a scene that has no programs yet, so its surface holds its poster`() throws {
        let folder = try scene(layers: [SyntheticScene.layer(model: "models/red.json", origin: (16, 16), size: (32, 32))], programs: nil)

        #expect(throws: WallpaperEngineScene.LoadError.noPrograms(folder.appending(path: ScenePrograms.fileName))) {
            try WallpaperEngineScene(folder: folder, device: self.device)
        }
    }

    @Test func `cannot load a scene whose programs do not compile`() throws {
        let broken = SyntheticScene.imageProgramsJSON.replacingOccurrences(of: "vertex Out main0", with: "vertex Out main0 syntax error")
        let folder = try scene(layers: [SyntheticScene.layer(model: "models/red.json", origin: (16, 16), size: (32, 32))], programs: broken)

        #expect(throws: WallpaperEngineScene.LoadError.noProgramCompiles) {
            try WallpaperEngineScene(folder: folder, device: self.device)
        }
    }

    @Test func `tells what it could not draw, once each`() throws {
        let folder = try scene(layers: [
            SyntheticScene.layer(model: "models/red.json", origin: (16, 16), size: (32, 32)),
            #"{"id": 9, "name": "music", "sound": ["sounds/music.mp3"]}"#,
            #"{"id": 10, "name": "clock", "text": {"value": "12:00"}}"#,
        ])

        let drawing = try WallpaperEngineScene(folder: folder, device: device)
        _ = try draw(drawing)
        _ = try draw(drawing, at: 1)

        #expect(drawing.notes.filter { $0.contains("clock") }.count == 1)
    }
}
