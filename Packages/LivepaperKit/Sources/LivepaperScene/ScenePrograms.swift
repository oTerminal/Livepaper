import Foundation

/// What an import leaves for drawing (`scene-programs.json`, beside the item's
/// files): every shader program the scene draws with, already translated from
/// the item's GLSL to Metal, with what is needed to fill its uniforms. The
/// extension compiles the Metal source and never translates anything; the app
/// translates at import, and again when `translator` is not the current one.
public struct ScenePrograms: Codable, Sendable {
    /// Where a uniform's value comes from when the scene's drawing does not supply it.
    public struct UniformSource: Codable, Sendable {
        /// Key into the material's and the scene's `constantshadervalues`.
        public let materialKey: String?
        /// The shader annotation's "default", as numbers.
        public let defaultValue: [Float]?

        public init(materialKey: String?, defaultValue: [Float]?) {
            self.materialKey = materialKey
            self.defaultValue = defaultValue
        }
    }

    public struct Entry: Codable, Sendable {
        public let shader: String
        public let defines: [String: Int]
        /// "item" (the scene's own source) or "builtin" (ours, written from scratch).
        public let origin: String
        public let program: TranslatedProgram
        public let uniforms: [String: UniformSource]
        /// Slot to the texture a sampler asks for when nothing is bound ("util/white", "_rt_FullFrameBuffer").
        public let samplerDefaults: [String: String]

        public init(
            shader: String, defines: [String: Int], origin: String, program: TranslatedProgram,
            uniforms: [String: UniformSource], samplerDefaults: [String: String]
        ) {
            self.shader = shader
            self.defines = defines
            self.origin = origin
            self.program = program
            self.uniforms = uniforms
            self.samplerDefaults = samplerDefaults
        }
    }

    public static let fileName = "scene-programs.json"

    /// Which translation wrote it: `ScenePrograms.currentTranslator` when it
    /// was the one this build carries. Anything else is prepared again by the app.
    public var translator: Int
    /// The tools' versions, for the record.
    public var tools: String
    /// Program key (shader and defines) to the program.
    public var programs: [String: Entry] = [:]
    /// Request signature (`ProgramRequest.signature`) to program key.
    public var requests: [String: String] = [:]
    /// Request signature to why it could not be translated. What uses it is not drawn.
    public var failures: [String: String] = [:]

    public init(translator: Int, tools: String) {
        self.translator = translator
        self.tools = tools
    }

    /// Bumped whenever translating the same scene would give different programs:
    /// the rules, our headers or our base materials changed.
    public static let currentTranslator = 1

    public func entry(for request: ProgramRequest) -> Entry? {
        requests[request.signature].flatMap { programs[$0] }
    }

    public static func read(from url: URL) throws -> ScenePrograms {
        try JSONDecoder().decode(ScenePrograms.self, from: Data(contentsOf: url))
    }

    /// Written whole or not at all, so a reader never sees half of it.
    public func write(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    /// The translator that wrote the file in `folder`, or nil when there is none that reads.
    public static func translator(in folder: URL) -> Int? {
        struct Stamp: Decodable { let translator: Int }
        let file = folder.appending(path: fileName, directoryHint: .notDirectory)
        guard let data = try? Data(contentsOf: file) else { return nil }
        return try? JSONDecoder().decode(Stamp.self, from: data).translator
    }
}

public enum ShaderStage: String, Codable, Sendable {
    case vertex = "vert"
    case fragment = "frag"
}

public struct Varying: Codable, Equatable, Sendable {
    public let name: String
    public let type: String

    public init(name: String, type: String) {
        self.name = name
        self.type = type
    }
}

public struct VertexAttribute: Codable, Equatable, Sendable {
    public let name: String
    public let type: String
    public let location: Int

    public init(name: String, type: String, location: Int) {
        self.name = name
        self.type = type
        self.location = location
    }
}

/// One stage after translation: the Metal source, and what drawing needs to bind it.
public struct TranslatedStage: Codable, Sendable {
    public var msl = ""
    /// The entry point in `msl`.
    public var entryPoint = "main0"
    /// Every uniform but the samplers, in one block at buffer index 0.
    public var uniforms = UniformLayout()
    /// Sampler name to texture and sampler index. `g_TextureN` is always N.
    public var samplers: [String: Int] = [:]
    /// Vertex: the varyings written, in location order. Fragment: those read.
    public var varyings: [Varying] = []
    /// Vertex attributes: `a_Position` 0, `a_TexCoord` 1, `a_Color` 2, …
    public var attributes: [VertexAttribute] = []

    public init() {}
}

public struct TranslatedProgram: Codable, Sendable {
    public let vertex: TranslatedStage
    public let fragment: TranslatedStage

    public init(vertex: TranslatedStage, fragment: TranslatedStage) {
        self.vertex = vertex
        self.fragment = fragment
    }
}

/// The std140 layout of the one uniform block a stage is given: every loose
/// `uniform` that is not a sampler, in the order declared.
public struct UniformLayout: Codable, Equatable, Sendable {
    public struct Member: Codable, Equatable, Sendable {
        public let name: String
        public let type: String
        public let arrayCount: Int?
        public let offset: Int
        /// An array element's stride: 16 for every std140 array of scalars or vectors.
        public let stride: Int
    }

    /// A loose uniform as a stage declares it: its GLSL type, its name, and
    /// how many elements it has when it is an array.
    public struct Declaration: Sendable {
        public let type: String
        public let name: String
        public let count: Int?

        public init(type: String, name: String, count: Int?) {
            self.type = type
            self.name = name
            self.count = count
        }
    }

    public var members: [Member] = []
    public var size = 16

    /// The most elements an array is laid out with. Wallpaper Engine's longest
    /// are its audio spectra of 64, and the block is packed again for every draw.
    public static let mostArrayElements = 1024

    public init() {}

    public static func std140(_ declarations: [Declaration]) -> UniformLayout {
        var layout = UniformLayout()
        var offset = 0
        for declaration in declarations {
            var (alignment, stride) = alignmentAndSize(declaration.type)
            // A shader's own count could be any number; multiplied out, a large one would overflow.
            let count = declaration.count.map { min(max($0, 0), mostArrayElements) }
            if count != nil {
                alignment = 16
                stride = (stride + 15) / 16 * 16
            }
            offset = (offset + alignment - 1) / alignment * alignment
            layout.members.append(
                Member(name: declaration.name, type: declaration.type, arrayCount: count, offset: offset, stride: stride)
            )
            offset += count.map { $0 * stride } ?? stride
        }
        layout.size = max(16, (offset + 15) / 16 * 16)
        return layout
    }

    private static func alignmentAndSize(_ type: String) -> (Int, Int) {
        switch type {
        case "float", "int", "uint", "bool": (4, 4)
        case "vec2", "ivec2", "uvec2", "bvec2": (8, 8)
        case "vec3", "ivec3", "uvec3", "bvec3": (16, 12)
        case "vec4", "ivec4", "uvec4", "bvec4": (16, 16)
        case "mat2": (16, 32)
        case "mat3": (16, 48)
        case "mat4": (16, 64)
        default: (16, 16)
        }
    }

    public func member(_ name: String) -> Member? { members.first { $0.name == name } }

    /// The block's bytes, each member given the numbers `value` has for it
    /// (whole numbers for an integer type) and zero where it has none. One
    /// number given for a vector fills every component.
    public func pack(_ value: (Member) -> [Float]?) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: size)
        for member in members {
            guard let values = value(member) else { continue }
            MemberPacking(member: member, values: values).write(into: &bytes)
        }
        return bytes
    }
}

/// One member's numbers written into a uniform block's bytes where the layout
/// puts them, as whole numbers for an integer type and as floats otherwise.
/// A number with no place in the block is left out.
private struct MemberPacking {
    let member: UniformLayout.Member
    let values: [Float]
    let isInteger: Bool

    init(member: UniformLayout.Member, values: [Float]) {
        self.member = member
        self.values = values
        isInteger = member.type.hasPrefix("int") || member.type.hasPrefix("ivec") || member.type.hasPrefix("uint")
            || member.type.hasPrefix("uvec") || member.type == "bool"
    }

    /// The numbers in a vector of the member's type: 1 for a scalar.
    private var components: Int {
        switch member.type {
        case "vec2", "ivec2", "uvec2": 2
        case "vec3", "ivec3", "uvec3": 3
        case "vec4", "ivec4", "uvec4": 4
        default: 1
        }
    }

    func write(into bytes: inout [UInt8]) {
        switch member.type {
        case "mat4":
            for (index, number) in values.prefix(16 * (member.arrayCount ?? 1)).enumerated() {
                put(number, at: member.offset + index * 4, into: &bytes)
            }
        case "mat3":
            writeMatrix3(into: &bytes)
        default:
            if let count = member.arrayCount { writeArray(of: count, into: &bytes) } else { writeVector(into: &bytes) }
        }
    }

    /// Nine numbers (a 3×3, column by column) or sixteen (a 4×4's columns); each column padded to 16 bytes.
    private func writeMatrix3(into bytes: inout [UInt8]) {
        for column in 0..<3 {
            for row in 0..<3 {
                let index = values.count == 9 ? column * 3 + row : column * 4 + row
                if index < values.count { put(values[index], at: member.offset + column * 16 + row * 4, into: &bytes) }
            }
        }
    }

    /// An array of scalars or vectors: the numbers in order, each element at the member's stride.
    private func writeArray(of count: Int, into bytes: inout [UInt8]) {
        let components = self.components
        for element in 0..<count {
            for component in 0..<components where element * components + component < values.count {
                put(values[element * components + component], at: member.offset + element * member.stride + component * 4, into: &bytes)
            }
        }
    }

    /// A scalar or a vector. One number given for a vector fills every component.
    private func writeVector(into bytes: inout [UInt8]) {
        for component in 0..<components {
            let number = values.count == 1 ? values[0] : component < values.count ? values[component] : 0
            put(number, at: member.offset + component * 4, into: &bytes)
        }
    }

    /// Four bytes, little-endian, at `offset`, unless they would fall outside the block.
    private func put(_ number: Float, at offset: Int, into bytes: inout [UInt8]) {
        guard offset >= 0, offset + 4 <= bytes.count else { return }
        let bits = isInteger ? UInt32(bitPattern: Int32(clamping: Int(clamping: number))) : number.bitPattern
        for index in 0..<4 { bytes[offset + index] = UInt8((bits >> (8 * UInt32(index))) & 0xFF) }
    }
}

/// One program drawing asks for: a shader, the combos its material and the
/// scene set, and which texture slots have something bound, which switches
/// combos such as MASK. The import translates every request a scene makes and
/// drawing looks each up by `signature`, so both build requests by these rules.
public struct ProgramRequest: Hashable, Sendable {
    public let shader: String
    public let combos: [String: Int]
    public let boundSlots: Set<Int>

    public init(shader: String, combos: [String: Int], boundSlots: Set<Int>) {
        self.shader = shader
        self.combos = combos
        self.boundSlots = boundSlots
    }

    public init(material: SceneMaterial, boundSlots: Set<Int>) {
        self.init(shader: material.shader, combos: material.combos, boundSlots: boundSlots)
    }

    public var signature: String {
        let combos = combos.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: ",")
        return "\(shader)|\(combos)|\(boundSlots.sorted().map(String.init).joined(separator: ","))"
    }

    /// The slots of an effect pass that will have a texture: slot 0, the
    /// input; textures the package carries; render targets (`_rt_…`); and binds.
    public static func boundSlots(of material: SceneMaterial, binds: [(name: String, slot: Int)], in files: SceneFiles) -> Set<Int> {
        var slots: Set<Int> = [0]
        for (slot, name) in material.textures.enumerated() {
            guard let name else { continue }
            if name.hasPrefix("_rt_") || files.contains(SceneFiles.texturePath(name)) { slots.insert(slot) }
        }
        for bind in binds { slots.insert(bind.slot) }
        return slots
    }

    /// The request an image layer's own material makes.
    public static func layer(_ layer: SceneLayer) -> ProgramRequest? {
        if layer.kind == .solid { return ProgramRequest(shader: "genericimage2", combos: [:], boundSlots: [0]) }
        guard let material = layer.material else { return nil }
        var combos = material.combos
        if layer.puppet != nil { combos["SKINNING"] = 1 }
        return ProgramRequest(shader: material.shader, combos: combos, boundSlots: [0])
    }

    /// Everything a scene draws with.
    public static func all(in document: SceneDocument) -> [ProgramRequest] {
        var requests: [ProgramRequest] = []
        func add(_ request: ProgramRequest?) {
            if let request, !requests.contains(request) { requests.append(request) }
        }
        for object in document.objects {
            switch object {
            case .layer(let layer):
                add(Self.layer(layer))
                for effect in layer.effects {
                    for pass in effect.passes {
                        guard let material = pass.material else { continue }
                        add(ProgramRequest(material: material, boundSlots: boundSlots(of: material, binds: pass.binds, in: document.files)))
                    }
                }
            case .particles(let particles):
                for definition in ParticleDefinition.tree(of: particles.file, in: document.files) {
                    guard let material = try? document.firstPass(of: definition.material) else { continue }
                    add(ProgramRequest(material: material, boundSlots: [0]))
                }
            case .sound, .other:
                break
            }
        }
        return requests
    }
}

extension ParticleDefinition {
    /// The system in `file` and its children, all the way down, each once.
    public static func tree(of file: String, in files: SceneFiles) -> [ParticleDefinition] {
        var definitions: [ParticleDefinition] = []
        var queue = [file]
        var seen = Set<String>()
        while let next = queue.popLast() {
            guard seen.insert(next).inserted, let definition = try? ParticleDefinition(files: files, file: next) else { continue }
            definitions.append(definition)
            queue += definition.children.map(\.file)
        }
        return definitions
    }
}
