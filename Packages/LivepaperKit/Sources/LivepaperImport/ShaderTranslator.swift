import Foundation
import LivepaperScene

/// Why a program did not translate: which stage, which step, and the first
/// thing the tool said about it.
public struct ShaderTranslationFailure: Error, Equatable, Sendable, CustomStringConvertible {
    public enum Step: String, Sendable {
        case preprocess
        case glslang = "glslang → SPIR-V"
        case spirvCross = "SPIRV-Cross → MSL"
    }

    public let stage: ShaderStage
    public let step: Step
    public let message: String

    public init(stage: ShaderStage, step: Step, message: String) {
        self.stage = stage
        self.step = step
        self.message = message
    }

    public var description: String { "\(stage.rawValue) \(step.rawValue): \(message)" }
}

/// Turns a scene's shaders, written in Wallpaper Engine's GLSL dialect, into
/// Metal Shading Language, in the three steps found to work on every
/// program the samples draw with:
///
/// 1. The combo defines and our `common.h` go in front of the source, and
///    glslang's preprocessor resolves `#include` against our headers
///    (`ShaderHeaders`), written from scratch.
/// 2. The GLSL 1.x declarations are rewritten for Vulkan GLSL 4.50: an
///    `attribute` gets a fixed location, a `varying` the location of the vertex
///    stage's varying of the same name, the loose uniforms go into one std140
///    block at `set = 1, binding = 0`, and a sampler `g_TextureN` is bound at N.
/// 3. glslang compiles that to SPIR-V, and SPIRV-Cross turns the SPIR-V into
///    MSL, taking its bindings from the SPIR-V's.
///
/// Every step is a run of one of the shader tools (`ShaderTools`), in a work
/// folder of its own that is removed afterwards.
public struct ShaderTranslator: Sendable {
    public let tools: ShaderTools

    public init(tools: ShaderTools) {
        self.tools = tools
    }

    /// The vertex stage, then the fragment stage against the vertex's varyings,
    /// on a thread of its own. Throws `ShaderTranslationFailure` for a program
    /// that does not translate, `ShaderToolError` when a tool cannot start or is
    /// stopped at a limit, and `CancellationError`.
    public func translate(vertex: String, fragment: String, defines: [(name: String, value: Int)]) async throws -> TranslatedProgram {
        try await onOwnThread { cancellation in
            try translateNow(vertex: vertex, fragment: fragment, defines: defines, cancellation: cancellation)
        }
    }

    /// The same, for work already on a thread of its own.
    func translateNow(
        vertex: String, fragment: String, defines: [(name: String, value: Int)], cancellation: Cancellation
    ) throws -> TranslatedProgram {
        let work = try WorkFolder(tools: tools, cancellation: cancellation)
        defer { work.remove() }
        let vertexStage = try translate(.vertex, source: vertex, defines: defines, varyings: [], in: work)
        let fragmentStage = try translate(.fragment, source: fragment, defines: defines, varyings: vertexStage.varyings, in: work)
        return TranslatedProgram(vertex: vertexStage, fragment: fragmentStage)
    }

    /// One stage, through the three steps. `varyings` are the vertex stage's,
    /// for a fragment stage to read at the same locations.
    private func translate(
        _ stage: ShaderStage, source: String, defines: [(name: String, value: Int)], varyings: [Varying], in work: WorkFolder
    ) throws -> TranslatedStage {
        func failure(_ step: ShaderTranslationFailure.Step, _ run: ToolRun) -> ShaderTranslationFailure {
            ShaderTranslationFailure(stage: stage, step: step, message: Self.firstError(in: run.said))
        }
        // The tools run in the work folder, so every path they see, and every message, is a short relative one.
        let input = "in.\(stage.rawValue)"
        try work.write(Self.prologue(stage, defines: defines, source: source), to: input)

        // 1. Preprocess, with our headers.
        let preprocessed = try work.run(tools.glslang, ["-E", "-I\(WorkFolder.include)", input])
        guard preprocessed.succeeded else { throw failure(.preprocess, preprocessed) }

        // 2. Rewrite the declarations.
        let rewrite = Self.rewrite(preprocessed.output, stage: stage, vertexVaryings: varyings)
        var translated = rewrite.stage
        let rewritten = "lp.\(stage.rawValue)"
        try work.write(rewrite.glsl, to: rewritten)

        // 3. SPIR-V, then MSL.
        let spirv = "\(stage.rawValue).spv"
        let compiled = try work.run(tools.glslang, ["-V", "--target-env", "vulkan1.1", "-o", spirv, rewritten])
        guard compiled.succeeded else { throw failure(.glslang, compiled) }
        let metal = "\(stage.rawValue).metal"
        let crossed = try work.run(
            tools.spirvCross, [spirv, "--msl", "--msl-version", "20400", "--msl-decoration-binding", "--output", metal]
        )
        guard crossed.succeeded, let msl = work.read(metal) else { throw failure(.spirvCross, crossed) }
        translated.msl = msl
        return translated
    }

    /// What glslang preprocesses: the version, the defines, `gl_FragColor`
    /// spelled as the output the rewrite declares, and `common.h`, then the source.
    static func prologue(_ stage: ShaderStage, defines: [(name: String, value: Int)], source: String) -> String {
        var text = "#version 450\n#extension GL_GOOGLE_include_directive : enable\n"
        for define in defines { text += "#define \(define.name) \(define.value)\n" }
        if stage == .fragment { text += "#define gl_FragColor _lpFragColor\n" }
        return text + "#include \"common.h\"\n" + source
    }

    /// Preprocessed GLSL 1.x to Vulkan GLSL 4.50, and what drawing needs to
    /// bind the stage: its attributes, varyings, samplers and uniform block.
    static func rewrite(_ preprocessed: String, stage: ShaderStage, vertexVaryings: [Varying]) -> (glsl: String, stage: TranslatedStage) {
        var rewrite = Rewrite(stage: stage, vertexVaryings: vertexVaryings)
        for line in preprocessed.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            rewrite.read(String(line))
        }
        return (rewrite.glsl, rewrite.translated)
    }

    // MARK: Messages

    /// The first error in what a tool said, without the work folder's names:
    /// `ERROR: line 12: 'foo' : undeclared identifier`.
    static func firstError(in said: String) -> String {
        let lines = said.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let error = lines.first { $0.contains("ERROR") || $0.contains("error") } ?? lines.first ?? "no message"
        guard let file = error.range(of: #"(?:[^ ]*/)?(?:in|lp)\.(?:vert|frag):"#, options: .regularExpression) else { return error }
        return error.replacingCharacters(in: file, with: "line ")
    }
}

/// One program's work folder under the temporary directory, with our headers
/// in it for `#include`, and the tools run inside it.
private struct WorkFolder {
    static let include = "include"

    let url: URL
    let tools: ShaderTools
    let cancellation: Cancellation

    init(tools: ShaderTools, cancellation: Cancellation) throws {
        url = FileManager.default.temporaryDirectory.appending(path: "livepaper-shaders-\(UUID())", directoryHint: .isDirectory)
        self.tools = tools
        self.cancellation = cancellation
        let headers = url.appending(path: Self.include, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: headers, withIntermediateDirectories: true)
            for (name, text) in ShaderHeaders.all {
                try Data(text.utf8).write(to: headers.appending(path: name, directoryHint: .notDirectory))
            }
        } catch {
            remove()
            throw error
        }
    }

    func write(_ text: String, to name: String) throws {
        try Data(text.utf8).write(to: url.appending(path: name, directoryHint: .notDirectory))
    }

    func read(_ name: String) -> String? {
        FileManager.default.contents(atPath: url.appending(path: name, directoryHint: .notDirectory).path)
            .flatMap { String(bytes: $0, encoding: .utf8) }
    }

    func run(_ tool: URL, _ arguments: [String]) throws -> ToolRun {
        try tools.run(tool, arguments, in: url, cancellation: cancellation)
    }

    func remove() {
        try? FileManager.default.removeItem(at: url)
    }
}

/// The rewrite of one stage, a line at a time: declarations out of GLSL 1.x
/// into Vulkan GLSL 4.50, everything else as it was.
private struct Rewrite {
    /// The locations the vertex attributes the samples use are given; any other gets one from 8 up.
    static let attributeLocations = [
        "a_Position": 0, "a_TexCoord": 1, "a_Color": 2, "a_TexCoordVec4": 3,
        "a_TexCoordVec4C1": 4, "a_Normal": 5, "a_Tangent4": 6, "a_TexCoordC2": 7,
    ]

    static let declaration = wellFormed(
        #"^\s*(attribute|varying|uniform)\s+(?:(?:lowp|mediump|highp)\s+)?(\w+)\s+(\w+)\s*(?:\[\s*(\w+)\s*\])?\s*;\s*$"#
    )

    /// A loose uniform, for the block.
    struct Member {
        let type: String
        let name: String
        let count: Int?
    }

    let stage: ShaderStage
    let vertexVaryings: [Varying]
    private var bindings = TranslatedStage()
    private var body: [String] = []
    private var block: [Member] = []
    private var nextAttribute = 8
    private var nextSampler = 8

    init(stage: ShaderStage, vertexVaryings: [Varying]) {
        self.stage = stage
        self.vertexVaryings = vertexVaryings
    }

    mutating func read(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if ["#version", "#extension", "#line", "#pragma"].contains(where: trimmed.hasPrefix) { return }
        let whole = line as NSString
        guard let match = Self.declaration.firstMatch(in: line, range: NSRange(location: 0, length: whole.length)) else {
            body.append(line)
            return
        }
        let (type, name) = (match.group(2, in: whole) ?? "", match.group(3, in: whole) ?? "")
        switch match.group(1, in: whole) {
        case "attribute": attribute(type, name)
        case "varying": varying(type, name)
        default: uniform(type, name, count: match.group(4, in: whole).flatMap { Int($0) })
        }
    }

    private mutating func attribute(_ type: String, _ name: String) {
        let location = Self.attributeLocations[name] ?? nextAttribute
        if Self.attributeLocations[name] == nil { nextAttribute += 1 }
        bindings.attributes.append(VertexAttribute(name: name, type: type, location: location))
        body.append("layout(location = \(location)) in \(type) \(name);")
    }

    /// Written by the vertex stage in order; read by the fragment stage where the vertex stage wrote the same name.
    private mutating func varying(_ type: String, _ name: String) {
        if stage == .vertex {
            body.append("layout(location = \(bindings.varyings.count)) out \(type) \(name);")
            bindings.varyings.append(Varying(name: name, type: type))
            return
        }
        guard let location = vertexVaryings.firstIndex(where: { $0.name == name }) else {
            // Read but never written by the vertex stage: a plain variable, zero.
            body.append("\(type) \(name);")
            return
        }
        bindings.varyings.append(Varying(name: name, type: type))
        let written = vertexVaryings[location].type
        if written == type {
            body.append("layout(location = \(location)) in \(type) \(name);")
        } else {
            // Declared with another type in the vertex stage: read what it wrote, and convert.
            body.append("layout(location = \(location)) in \(written) _lpIn_\(name);")
            body.append("\(type) \(name) = \(type)(_lpIn_\(name));")
        }
    }

    /// A sampler is bound at its slot; anything else joins the block, once.
    private mutating func uniform(_ type: String, _ name: String, count: Int?) {
        guard type.hasPrefix("sampler") else {
            if !block.contains(where: { $0.name == name }) { block.append(Member(type: type, name: name, count: count)) }
            return
        }
        let binding = ShaderAnnotations.textureSlot(name) ?? nextSampler
        if ShaderAnnotations.textureSlot(name) == nil { nextSampler += 1 }
        bindings.samplers[name] = binding
        body.append("layout(set = 0, binding = \(binding)) uniform \(type) \(name);")
    }

    /// The stage's GLSL: the output a fragment stage writes, the block, then the rest.
    var glsl: String {
        var text = "#version 450\n"
        if stage == .fragment { text += "layout(location = 0) out vec4 _lpFragColor;\n" }
        if !block.isEmpty {
            text += "layout(std140, set = 1, binding = 0) uniform LPUniforms {\n"
            for member in block { text += "    \(member.type) \(member.name)\(member.count.map { "[\($0)]" } ?? "");\n" }
            text += "};\n"
        }
        return text + body.joined(separator: "\n")
    }

    /// What drawing needs to bind the stage, with where it finds each member of the block.
    var translated: TranslatedStage {
        var translated = bindings
        translated.uniforms = UniformLayout.std140(block.map { UniformLayout.Declaration(type: $0.type, name: $0.name, count: $0.count) })
        return translated
    }
}
