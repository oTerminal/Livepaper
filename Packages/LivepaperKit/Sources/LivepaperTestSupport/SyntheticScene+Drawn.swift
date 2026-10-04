import Foundation

// Scenes for the drawing's tests: a folder as the library keeps one, puppets,
// and programs written by hand in Metal the way the import's translation
// writes them, so that drawing can be tested without the shader tools.

extension SyntheticScene {
    /// A scene wallpaper's folder: `project.json`, and `scene.pkg` holding `entries`.
    /// `programs` is the JSON of its `scene-programs.json`, when it has one.
    public static func writeFolder(
        at folder: URL, entries: [Entry], project: String = #"{"type": "scene", "file": "scene.json", "title": "Synthetic"}"#,
        programs: String? = nil
    ) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(project.utf8).write(to: folder.appending(path: "project.json"))
        try package(entries).write(to: folder.appending(path: "scene.pkg"))
        if let programs { try Data(programs.utf8).write(to: folder.appending(path: "scene-programs.json")) }
    }

    /// A one-colour RGBA8888 texture, `width` by `height`, with no sprite sheet.
    public static func solidTexture(_ colour: Colour, width: Int, height: Int, alpha: UInt8 = 255) -> Data {
        var pixels = Data(capacity: width * height * 4)
        for _ in 0..<width * height { pixels.append(contentsOf: [colour.red, colour.green, colour.blue, alpha]) }
        return texture([RawImage(width: width, height: height, pixels: pixels)], frames: nil, compressed: false)
    }

    /// An image layer of `size` at `origin`, drawn from `model`. Each of `fields` adds one field.
    public static func layer(model: String, origin: (Double, Double), size: (Double, Double), fields: [String: String] = [:]) -> String {
        let plain = [
            "image": "\"\(model)\"",
            "origin": "\"\(origin.0) \(origin.1) 0\"",
            "size": "\"\(size.0) \(size.1)\"",
            "visible": "true",
        ]
        let merged = plain.merging(fields) { _, new in new }
        return "{" + merged.keys.sorted().map { "\"\($0)\": \(merged[$0] ?? "null")" }.joined(separator: ", ") + "}"
    }

    // MARK: Puppets

    /// A puppet (`.mdl`, "MDLV0023") of one quad in two triangles, `half` pixels
    /// either way of its centre, every vertex on bone 0; one bone, and one
    /// animation of `frames` frames that moves bone 0 by `step` pixels along x a frame.
    public static func puppet(half: Float, frames: Int, step: Float, material: String = "materials/puppet.json") -> Data {
        var data = Data()
        data.append(contentsOf: Array("MDLV0023".utf8) + [0])
        for _ in 0..<3 { data.appendWord(0) }
        data.append(contentsOf: Array(material.utf8) + [0])
        data.append(contentsOf: [0, 0, 0])
        data.appendWord(0x0180_000F)
        let corners: [(position: SIMD2<Float>, uv: SIMD2<Float>)] = [
            (SIMD2(-half, -half), SIMD2(0, 1)), (SIMD2(half, -half), SIMD2(1, 1)),
            (SIMD2(half, half), SIMD2(1, 0)), (SIMD2(-half, half), SIMD2(0, 0)),
        ]
        data.appendWord(UInt32(corners.count * 80))
        for corner in corners {
            for value in [corner.position.x, corner.position.y, 0, 0, 0, 1, 1, 0, 0, 1] { data.appendFloat(value) }
            for bone in [UInt32(0), 0, 0, 0] { data.appendWord(bone) }
            for weight in [Float(1), 0, 0, 0] { data.appendFloat(weight) }
            data.appendFloat(corner.uv.x)
            data.appendFloat(corner.uv.y)
        }
        let indices: [UInt16] = [0, 1, 2, 0, 2, 3]
        data.appendWord(UInt32(indices.count * 2))
        for index in indices { data.append(contentsOf: [UInt8(index & 0xFF), UInt8(index >> 8)]) }
        // The part table: one part of every index.
        for value in [UInt32(0), 0, UInt32(indices.count), 0] { data.appendWord(value) }
        data.append(contentsOf: Array("MDLS0004".utf8) + [0])
        data.appendWord(0)
        data.appendWord(1)
        data.append(contentsOf: Array("root".utf8) + [0])
        data.appendWord(0)
        data.appendWord(UInt32(bitPattern: -1))
        data.appendWord(64)
        for value in [Float(1), 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1] { data.appendFloat(value) }
        data.append(0)
        data.append(contentsOf: Array("MDLA0006".utf8) + [0])
        data.appendWord(0)
        data.appendWord(1)
        data.appendWord(1)
        data.appendWord(0)
        data.append(contentsOf: Array("sway".utf8) + [0])
        data.append(contentsOf: Array("loop".utf8) + [0])
        data.appendFloat(10)
        data.appendWord(UInt32(frames))
        data.appendWord(0)
        data.appendWord(1)
        data.appendWord(0)
        data.appendWord(UInt32(frames * 36))
        for frame in 0..<frames {
            for value in [Float(frame) * step, 0, 0, 0, 0, 0, 1, 1, 1] { data.appendFloat(value) }
        }
        return data
    }

    // MARK: Programs

    /// `scene-programs.json` with one program, a textured and tinted quad
    /// written in Metal as the translation would write `genericimage2`,
    /// answering the request of a plain image layer that uses it.
    public static let imageProgramsJSON = """
        {"translator": 1, "tools": "written by hand",
         "programs": {"genericimage2|": {"shader": "genericimage2", "defines": {}, "origin": "builtin",
           "uniforms": {"g_Color4": {"defaultValue": [1, 1, 1, 1]}}, "samplerDefaults": {},
           "program": {
             "vertex": {"entryPoint": "main0", "msl": \(jsonString(imageVertex)),
               "uniforms": {"size": 80, "members": [
                 {"name": "g_ModelViewProjectionMatrix", "type": "mat4", "offset": 0, "stride": 64},
                 {"name": "g_FrameRect", "type": "vec4", "offset": 64, "stride": 16}]},
               "samplers": {}, "varyings": [{"name": "v_TexCoord", "type": "vec2"}],
               "attributes": [{"name": "a_Position", "type": "vec3", "location": 0},
                              {"name": "a_TexCoord", "type": "vec2", "location": 1}]},
             "fragment": {"entryPoint": "main0", "msl": \(jsonString(imageFragment)),
               "uniforms": {"size": 16, "members": [{"name": "g_Color4", "type": "vec4", "offset": 0, "stride": 16}]},
               "samplers": {"g_Texture0": 0}, "varyings": [{"name": "v_TexCoord", "type": "vec2"}], "attributes": []}}}},
         "requests": {"genericimage2||0": "genericimage2|"},
         "failures": {}}
        """

    private static let imageVertex = """
        #include <metal_stdlib>
        using namespace metal;
        struct Uniforms { float4x4 g_ModelViewProjectionMatrix; float4 g_FrameRect; };
        struct In { float3 a_Position [[attribute(0)]]; float2 a_TexCoord [[attribute(1)]]; };
        struct Out { float4 position [[position]]; float2 v_TexCoord [[user(locn0)]]; };
        vertex Out main0(In in [[stage_in]], constant Uniforms& u [[buffer(0)]]) {
            Out out;
            out.position = u.g_ModelViewProjectionMatrix * float4(in.a_Position, 1.0);
            out.v_TexCoord = u.g_FrameRect.xy + in.a_TexCoord * u.g_FrameRect.zw;
            return out;
        }
        """

    private static let imageFragment = """
        #include <metal_stdlib>
        using namespace metal;
        struct Uniforms { float4 g_Color4; };
        struct In { float2 v_TexCoord [[user(locn0)]]; };
        fragment float4 main0(In in [[stage_in]], constant Uniforms& u [[buffer(0)]],
                              texture2d<float> g_Texture0 [[texture(0)]], sampler g_Texture0Smplr [[sampler(0)]]) {
            return g_Texture0.sample(g_Texture0Smplr, in.v_TexCoord) * u.g_Color4;
        }
        """

    private static func jsonString(_ text: String) -> String {
        let empty = "[\"\"]"
        let data = (try? JSONSerialization.data(withJSONObject: [text], options: [])) ?? Data(empty.utf8)
        return String((String(bytes: data, encoding: .utf8) ?? empty).dropFirst().dropLast())
    }
}

extension Data {
    fileprivate mutating func appendWord(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    fileprivate mutating func appendFloat(_ value: Float) {
        appendWord(value.bitPattern)
    }
}
