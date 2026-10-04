import Foundation
import Testing
import LivepaperImport
import LivepaperScene

/// Wallpaper Engine's GLSL dialect to Metal, through the real shader tools, on
/// shaders written here in that dialect.
@Suite(.enabled(if: ShaderToolsHelper.shouldRun))
struct ShaderTranslatorTests {
    let translator: ShaderTranslator

    init() throws {
        translator = ShaderTranslator(tools: try ShaderToolsHelper.required())
    }

    /// What an effect's vertex stage looks like: a combo, attributes, varyings and loose uniforms.
    static let vertex = """
        // [COMBO] {"material":"Ripple","combo":"RIPPLE","type":"options","default":0}
        #include "common.h"

        uniform mat4 g_ModelViewProjectionMatrix;
        uniform float g_Time;
        uniform vec2 g_Offset; // {"material":"offset","default":"0 0"}

        attribute vec3 a_Position;
        attribute vec2 a_TexCoord;

        varying vec2 v_TexCoord;
        varying vec4 v_Corner;

        void main() {
            gl_Position = mul(vec4(a_Position, 1.0), g_ModelViewProjectionMatrix);
            v_TexCoord = a_TexCoord + g_Offset;
        #if RIPPLE
            v_TexCoord.x += sin(g_Time + a_TexCoord.y * 10.0) * 0.01;
        #endif
            v_Corner = vec4(a_TexCoord, 0.0, 1.0);
        }
        """

    /// Its fragment stage: two textures, one of them switching a combo, uniforms of three sizes.
    static let fragment = """
        #include "common.h"

        uniform sampler2D g_Texture0; // {"hidden":true}
        uniform sampler2D g_Texture1; // {"combo":"MASK","default":"util/white"}
        uniform float g_Alpha; // {"material":"alpha","default":1}
        uniform vec3 g_Colour; // {"material":"colour","default":"1 1 1"}
        uniform vec4 g_Params;

        varying vec2 v_TexCoord;
        varying vec4 v_Corner;

        void main() {
            vec4 albedo = texSample2D(g_Texture0, v_TexCoord);
        #if MASK
            albedo.a *= texSample2D(g_Texture1, v_TexCoord).r;
        #endif
            gl_FragColor = vec4(albedo.rgb * g_Colour, albedo.a * saturate(g_Alpha)) + v_Corner * frac(g_Params.x);
        }
        """

    func translate(
        vertex: String = vertex, fragment: String = fragment, defines: [(name: String, value: Int)] = [("MASK", 1), ("RIPPLE", 0)]
    ) async throws -> TranslatedProgram {
        try await translator.translate(vertex: vertex, fragment: fragment, defines: defines)
    }

    @Test func `a program in the dialect becomes Metal with main0`() async throws {
        let program = try await translate()

        #expect(program.vertex.entryPoint == "main0" && program.fragment.entryPoint == "main0")
        #expect(program.vertex.msl.contains("vertex main0_out main0("))
        #expect(program.fragment.msl.contains("fragment main0_out main0("))
        #expect(program.vertex.attributes == [
            VertexAttribute(name: "a_Position", type: "vec3", location: 0), VertexAttribute(name: "a_TexCoord", type: "vec2", location: 1),
        ])
        #expect(program.vertex.varyings == [Varying(name: "v_TexCoord", type: "vec2"), Varying(name: "v_Corner", type: "vec4")])
        #expect(program.fragment.varyings == program.vertex.varyings)
        #expect(program.vertex.msl.contains("float3 a_Position [[attribute(0)]]"))
        #expect(program.fragment.msl.contains("float4 v_Corner [[user(locn1)]]"), "read where the vertex stage wrote it")
    }

    @Test func `a sampler g_TextureN is bound at N`() async throws {
        let program = try await translate()

        #expect(program.fragment.samplers == ["g_Texture0": 0, "g_Texture1": 1])
        #expect(program.fragment.msl.contains("texture2d<float> g_Texture0 [[texture(0)]]"))
        #expect(program.fragment.msl.contains("sampler g_Texture0Smplr [[sampler(0)]]"))
        #expect(program.fragment.msl.contains("texture2d<float> g_Texture1 [[texture(1)]]"))
    }

    @Test func `the loose uniforms are one std140 block at buffer 0, laid out as the manifest says`() async throws {
        let program = try await translate()

        let fragment = program.fragment.uniforms
        #expect(fragment.members.map(\.name) == ["g_Alpha", "g_Colour", "g_Params"])
        #expect(fragment.members.map(\.offset) == [0, 16, 32])
        #expect(fragment.size == 48)
        #expect(program.vertex.uniforms.members.map(\.name) == ["g_ModelViewProjectionMatrix", "g_Time", "g_Offset"])
        #expect(program.vertex.uniforms.members.map(\.offset) == [0, 64, 72])
        // SPIRV-Cross lays out the Metal struct to the same offsets: the vec3 is a float3, which Metal aligns to 16.
        #expect(program.fragment.msl.contains("struct LPUniforms\n{\n    float g_Alpha;\n    float3 g_Colour;\n    float4 g_Params;\n};"))
        #expect(program.fragment.msl.contains("constant LPUniforms&"))
        #expect(program.fragment.msl.contains("[[buffer(0)]]"))
    }

    @Test func `a combo changes the Metal`() async throws {
        let still = try await translate(defines: [("MASK", 1), ("RIPPLE", 0)])
        let rippling = try await translate(defines: [("MASK", 1), ("RIPPLE", 1)])

        #expect(still.vertex.msl != rippling.vertex.msl)
        #expect(!still.vertex.msl.contains("sin("))
        #expect(rippling.vertex.msl.contains("sin("))
    }

    @Test func `a varying declared as another type in the fragment stage is read as the vertex wrote it`() async throws {
        let fragment = """
            varying vec2 v_TexCoord;
            varying vec2 v_Corner;

            void main() {
                gl_FragColor = vec4(v_TexCoord, v_Corner);
            }
            """

        let program = try await translate(fragment: fragment)

        #expect(program.fragment.varyings == [Varying(name: "v_TexCoord", type: "vec2"), Varying(name: "v_Corner", type: "vec2")])
        #expect(program.fragment.msl.contains("float4 _lpIn_v_Corner [[user(locn1)]]"))
    }

    @Test func `a varying the vertex stage never writes is a variable of the fragment stage's own`() async throws {
        let fragment = """
            varying vec2 v_TexCoord;
            varying vec2 v_Scroll;

            void main() {
                gl_FragColor = vec4(v_TexCoord + v_Scroll, 0.0, 1.0);
            }
            """

        let program = try await translate(fragment: fragment)

        #expect(program.fragment.varyings == [Varying(name: "v_TexCoord", type: "vec2")])
    }

    @Test func `a shader that does not compile fails at glslang, saying where`() async throws {
        let broken = """
            varying vec2 v_TexCoord;

            void main() {
                gl_FragColor = vec4(v_TexCoord, undeclaredThing, 1.0);
            }
            """

        let error = await #expect(throws: ShaderTranslationFailure.self) { try await translate(fragment: broken) }

        #expect(error?.stage == .fragment)
        #expect(error?.step == .glslang)
        let message = try #require(error?.message)
        #expect(message.hasPrefix("ERROR: line "))
        #expect(message.contains("'undeclaredThing' : undeclared identifier"))
        #expect(!message.contains("/"), "no path of the work folder: \(message)")
    }

    @Test func `an include that is not one of ours fails at the preprocessor`() async throws {
        let error = await #expect(throws: ShaderTranslationFailure.self) {
            try await translate(vertex: "#include \"common_fog.h\"\n" + Self.vertex)
        }

        #expect(error?.stage == .vertex)
        #expect(error?.step == .preprocess)
        #expect(error?.message.contains("common_fog.h") == true)
    }

    @Test func `our headers give the dialect's spellings`() async throws {
        let fragment = """
            #include "common_blending.h"
            #include "common_blur.h"
            #include "common_perspective.h"

            uniform sampler2D g_Texture0;
            varying vec2 v_TexCoord;

            void main() {
                vec4 blurred = blur13a(v_TexCoord, vec2(0.01, 0.0));
                mat3 warp = squareToQuad(vec2(0.0), vec2(1.0, 0.0), vec2(1.0), vec2(0.0, 1.0));
                vec3 hsv = rgb2hsv(blurred.rgb);
                vec4 sample = texSample2D(g_Texture0, frac(mul(vec3(v_TexCoord, 1.0), warp).xy));
                gl_FragColor = vec4(ApplyBlending(9, hsv2rgb(hsv), sample.rgb, 0.5), lerp(0.0, 1.0, greyscale(sample.rgb)));
            }
            """

        let program = try await translate(fragment: fragment)

        #expect(program.fragment.msl.contains("fragment main0_out main0("))
    }

    @Test(.enabled(if: GPU.device != nil))
    func `the Metal compiles`() async throws {
        let device = try #require(GPU.device)
        for defines in [[("MASK", 0), ("RIPPLE", 0)], [("MASK", 1), ("RIPPLE", 1)]] as [[(name: String, value: Int)]] {
            let program = try await translate(defines: defines)

            #expect(GPU.compile(program.vertex.msl, on: device) == nil)
            #expect(GPU.compile(program.fragment.msl, on: device) == nil)
        }
    }
}
