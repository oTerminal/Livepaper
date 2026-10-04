import Foundation
import Testing
import LivepaperImport

/// What a shader says about itself in comments, on shaders written here in
/// Wallpaper Engine's dialect.
struct ShaderAnnotationsTests {
    static let combos: [Row<String, [String: Int]>] = [
        Row("a combo with its default", #"// [COMBO] {"material":"Mask","combo":"MASK","type":"options","default":1}"#, ["MASK": 1]),
        Row("a combo with no default is 0", #"// [COMBO] {"material":"Mode","combo":"MODE","type":"options"}"#, ["MODE": 0]),
        Row("indented and spaced out", #"    //   [COMBO]   {"combo":"KERNEL","default":2}  "#, ["KERNEL": 2]),
        Row(
            "the first declaration of a combo counts",
            "// [COMBO] {\"combo\":\"PASSES\",\"default\":1}\n// [COMBO] {\"combo\":\"PASSES\",\"default\":3}",
            ["PASSES": 1]
        ),
        Row("a combo switched off is not one", #"// [COMBO_OFF] {"combo":"AUDIO","default":1}"#, [:]),
        Row("nor is one written the other way round", #"// [OFF_COMBO] {"combo":"AUDIO","default":1}"#, [:]),
        Row("a leading zero, which JSON refuses, is dropped", #"// [COMBO] {"combo":"STEPS","default":02,"range":[0,01]}"#, ["STEPS": 2]),
        Row("a comment that only mentions combos is not one", "// see [COMBO] lines above", [:]),
    ]

    @Test(arguments: combos)
    func `combo lines give the combos and their defaults`(row: Row<String, [String: Int]>) {
        let annotations = ShaderAnnotations(sources: [row.input])

        #expect(Dictionary(annotations.combos.map { ($0.name, $0.defaultValue) }) { first, _ in first } == row.expected)
    }

    @Test func `a combo switched off is listed as such, and left undefined`() {
        let annotations = ShaderAnnotations(sources: [#"// [COMBO_OFF] {"combo":"AUDIO","default":1}"#])

        #expect(annotations.disabledCombos == ["AUDIO"])
        #expect(annotations.defines(explicit: [:], boundSlots: []).isEmpty)
    }

    @Test func `JSON that cannot be read even repaired is kept aside`() {
        let annotations = ShaderAnnotations(sources: [#"// [COMBO] {"combo":"BROKEN","default":}"#, "uniform float g_Odd; // {not json}"])

        #expect(annotations.combos.isEmpty)
        #expect(annotations.badJSON.count == 2)
        #expect(annotations.uniforms["g_Odd"]?.json == nil)
    }

    // MARK: Uniforms

    struct Expected: Sendable {
        var type: String
        var arrayCount: Int?
        var materialKey: String?
        var numbers: [Float]?
    }

    static let uniforms: [Row<String, Expected>] = [
        Row("a bare uniform", "uniform float g_Time;", Expected(type: "float")),
        Row(
            "a number default and a material key",
            #"uniform float g_Speed; // {"material":"speed","default":1.5}"#,
            Expected(type: "float", materialKey: "speed", numbers: [1.5])
        ),
        Row(
            "a default as a string of numbers",
            #"uniform vec3 g_Tint; // {"material":"colour","default":"1 0.5 0.25","type":"color"}"#,
            Expected(type: "vec3", materialKey: "colour", numbers: [1, 0.5, 0.25])
        ),
        Row(
            "a default as an array",
            #"uniform vec2 g_Scale; // {"material":"scale","default":[2,3]}"#,
            Expected(type: "vec2", materialKey: "scale", numbers: [2, 3])
        ),
        Row("a precision qualifier", "uniform highp vec4 g_Params;", Expected(type: "vec4")),
        Row("an array", "uniform mat4 g_Bones[32];", Expected(type: "mat4", arrayCount: 32)),
        Row(
            "a leading zero in the annotation",
            #"uniform float g_Amount; // {"material":"amount","default":0.5,"range":[0,01]}"#,
            Expected(type: "float", materialKey: "amount", numbers: [0.5])
        ),
        Row(
            "a comment that is not JSON",
            "uniform float g_Phase; // the phase, in radians",
            Expected(type: "float")
        ),
    ]

    @Test(arguments: uniforms)
    func `a uniform's annotation gives its material key and default`(row: Row<String, Expected>) throws {
        let annotations = ShaderAnnotations(sources: [row.input])

        let uniform = try #require(annotations.uniforms.values.first)
        #expect(annotations.uniforms.count == 1)
        #expect(uniform.type == row.expected.type)
        #expect(uniform.arrayCount == row.expected.arrayCount)
        #expect(uniform.materialKey == row.expected.materialKey)
        #expect(uniform.defaultNumbers == row.expected.numbers)
    }

    @Test func `an annotated declaration in the fragment stage wins over a bare one in the vertex stage`() {
        let vertex = "uniform float g_Strength;\nuniform float g_Time;"
        let fragment = #"uniform float g_Time; // {"material":"ignored","default":9}"# + "\n" +
            #"uniform float g_Strength; // {"material":"strength","default":0.25}"#

        let annotations = ShaderAnnotations(sources: [vertex, fragment])

        #expect(annotations.uniformOrder == ["g_Strength", "g_Time"])
        #expect(annotations.uniforms["g_Strength"]?.materialKey == "strength")
        #expect(annotations.uniforms["g_Strength"]?.defaultNumbers == [0.25])
        #expect(annotations.uniforms["g_Time"]?.materialKey == "ignored", "an annotation is kept wherever it comes")
    }

    @Test func `an annotated declaration is not undone by a bare one after it`() {
        let annotated = #"uniform float g_Alpha; // {"material":"alpha","default":1}"#

        let annotations = ShaderAnnotations(sources: [annotated, "uniform float g_Alpha;"])

        #expect(annotations.uniforms["g_Alpha"]?.materialKey == "alpha")
    }

    @Test func `a texture's default and the combo it switches`() {
        let annotations = ShaderAnnotations(sources: [
            #"uniform sampler2D g_Texture0; // {"hidden":true}"#,
            #"uniform sampler2D g_Texture1; // {"combo":"MASK","default":"util/white","label":"Mask"}"#,
            #"uniform sampler2D g_Texture2; // {"combo":"NOISE"}"#,
        ])

        #expect(annotations.uniforms["g_Texture1"]?.defaultValue as? String == "util/white")
        #expect(annotations.textureCombos.sorted { $0.slot < $1.slot }.map { "\($0.slot)=\($0.combo)" } == ["1=MASK", "2=NOISE"])
    }

    static let slots: [Row<String, Int?>] = [
        Row("g_Texture0", "g_Texture0", 0),
        Row("g_Texture12", "g_Texture12", 12),
        Row("a sampler of another name", "u_Noise", nil),
        Row("g_Texture with no number", "g_TextureMask", nil),
    ]

    @Test(arguments: slots)
    func `a sampler's slot is the number after g_Texture`(row: Row<String, Int?>) {
        #expect(ShaderAnnotations.textureSlot(row.input) == row.expected)
    }

    // MARK: Line breaks

    @Test func `a file with CRLF line breaks reads as one with LF`() {
        let lines = [
            #"// [COMBO] {"combo":"BLENDMODE","default":9}"#,
            #"uniform float g_Alpha; // {"material":"alpha","default":1}"#,
            #"uniform sampler2D g_Texture1; // {"combo":"MASK"}"#,
            "void main() {}",
        ]
        let crlf = ShaderAnnotations(sources: [lines.joined(separator: "\r\n")])
        let lf = ShaderAnnotations(sources: [lines.joined(separator: "\n")])

        #expect(crlf.combos.map(\.name) == ["BLENDMODE"])
        #expect(crlf.uniformOrder == lf.uniformOrder)
        #expect(crlf.uniforms["g_Alpha"]?.materialKey == "alpha")
        #expect(crlf.defines(explicit: [:], boundSlots: [0]).map(\.name) == lf.defines(explicit: [:], boundSlots: [0]).map(\.name))
    }

    // MARK: Defines

    struct Program: Sendable {
        var explicit: [String: Int]
        var boundSlots: Set<Int>
    }

    static let shader = """
        // [COMBO] {"combo":"VERTICAL","default":0}
        // [COMBO] {"combo":"KERNEL","default":2}
        // [COMBO] {"combo":"MASK","default":1}
        uniform sampler2D g_Texture0;
        uniform sampler2D g_Texture1; // {"combo":"MASK"}
        uniform sampler2D g_Texture2; // {"combo":"NOISE"}
        """

    static let defines: [Row<Program, [String]>] = [
        Row(
            "the defaults, sorted by name, the textures' combos off",
            Program(explicit: [:], boundSlots: [0]),
            ["KERNEL=2", "MASK=0", "NOISE=0", "VERTICAL=0"]
        ),
        Row(
            "a texture that is bound switches its combo on",
            Program(explicit: [:], boundSlots: [0, 2]),
            ["KERNEL=2", "MASK=0", "NOISE=1", "VERTICAL=0"]
        ),
        Row(
            "a bound texture beats the combo's own default",
            Program(explicit: [:], boundSlots: [0, 1]),
            ["KERNEL=2", "MASK=1", "NOISE=0", "VERTICAL=0"]
        ),
        Row(
            "what the material sets beats both",
            Program(explicit: ["MASK": 0, "VERTICAL": 1], boundSlots: [0, 1]),
            ["KERNEL=2", "MASK=0", "NOISE=0", "VERTICAL=1"]
        ),
        Row(
            "a combo the shader does not declare is still defined",
            Program(explicit: ["AUDIOPROCESSING": 1], boundSlots: [0]),
            ["AUDIOPROCESSING=1", "KERNEL=2", "MASK=0", "NOISE=0", "VERTICAL=0"]
        ),
    ]

    @Test(arguments: defines)
    func `defines come from the defaults, then the bound textures, then the material`(row: Row<Program, [String]>) {
        let annotations = ShaderAnnotations(sources: [Self.shader])

        let defines = annotations.defines(explicit: row.input.explicit, boundSlots: row.input.boundSlots)

        #expect(defines.map { "\($0.name)=\($0.value)" } == row.expected)
    }
}
