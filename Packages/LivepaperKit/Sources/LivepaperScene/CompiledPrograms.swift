import Foundation
import Metal

/// A translated program, compiled for this device, with its pipelines made as they are first needed.
final class CompiledProgram {
    let entry: ScenePrograms.Entry
    let vertexFunction: any MTLFunction
    let fragmentFunction: any MTLFunction
    var pipelines: [String: any MTLRenderPipelineState] = [:]

    init(entry: ScenePrograms.Entry, vertexFunction: any MTLFunction, fragmentFunction: any MTLFunction) {
        self.entry = entry
        self.vertexFunction = vertexFunction
        self.fragmentFunction = fragmentFunction
    }

    var name: String { entry.shader }
    var vertex: TranslatedStage { entry.program.vertex }
    var fragment: TranslatedStage { entry.program.fragment }
}

/// How a material's output goes onto what is under it.
enum Blending: String {
    /// Replaces.
    case normal
    /// Over, by the source's alpha.
    case translucent
    /// Adds, by the source's alpha.
    case additive

    init(_ material: String) {
        self = Blending(rawValue: material) ?? .normal
    }

    func apply(to attachment: MTLRenderPipelineColorAttachmentDescriptor) {
        switch self {
        case .normal:
            attachment.isBlendingEnabled = false
        case .translucent:
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .sourceAlpha
            attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            attachment.sourceAlphaBlendFactor = .one
            attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        case .additive:
            attachment.isBlendingEnabled = true
            attachment.sourceRGBBlendFactor = .sourceAlpha
            attachment.destinationRGBBlendFactor = .one
            attachment.sourceAlphaBlendFactor = .zero
            attachment.destinationAlphaBlendFactor = .one
        }
    }
}

/// The vertices drawing feeds a program, in one buffer at `bufferIndex`.
enum VertexLayout {
    /// Position (three floats) and UV (two): quads.
    static let quadStride = 20
    /// Position, UV and colour (four floats): particles.
    static let particleStride = 36
    /// Position, UV, bone indices (four floats) and bone weights (four): puppets.
    static let skinnedStride = 52
    static let bufferIndex = 16
    /// The vertex attributes a pipeline has, at locations 0 to 30.
    static let maxAttributes = 31

    static func stride(for attributes: [VertexAttribute]) -> Int {
        let names = Set(attributes.map(\.name))
        if names.contains("a_BlendIndices") { return skinnedStride }
        if names.contains("a_Color") { return particleStride }
        return quadStride
    }

    static func descriptor(for attributes: [VertexAttribute]) -> MTLVertexDescriptor {
        let descriptor = MTLVertexDescriptor()
        // A location past the ones a pipeline has is out of the descriptor's range.
        for attribute in attributes where (0..<maxAttributes).contains(attribute.location) {
            let (format, offset): (MTLVertexFormat, Int) = switch attribute.name {
            case "a_Position": (.float3, 0)
            case "a_TexCoord": (.float2, 12)
            case "a_Color": (.float4, 20)
            case "a_BlendIndices": (.float4, 20)
            case "a_BlendWeights": (.float4, 36)
            // Attributes nothing feeds read the UV again, so that the pipeline links.
            default: (.float2, 12)
            }
            descriptor.attributes[attribute.location].format = format
            descriptor.attributes[attribute.location].offset = offset
            descriptor.attributes[attribute.location].bufferIndex = bufferIndex
        }
        descriptor.layouts[bufferIndex].stride = stride(for: attributes)
        return descriptor
    }
}

/// Compiles the scene's translated programs at load, and makes their pipelines on first use.
final class CompiledPrograms {
    private let device: any MTLDevice
    let manifest: ScenePrograms
    private var programs: [String: CompiledProgram] = [:]
    /// Programs that did not translate or compile, for the log. What uses them is not drawn.
    private(set) var failures: [String] = []

    init(device: any MTLDevice, manifest: ScenePrograms) {
        self.device = device
        self.manifest = manifest
        for (key, entry) in manifest.programs.sorted(by: { $0.key < $1.key }) {
            do {
                let vertex = try device.makeLibrary(source: entry.program.vertex.msl, options: nil)
                let fragment = try device.makeLibrary(source: entry.program.fragment.msl, options: nil)
                guard
                    let vertexFunction = vertex.makeFunction(name: entry.program.vertex.entryPoint),
                    let fragmentFunction = fragment.makeFunction(name: entry.program.fragment.entryPoint)
                else {
                    failures.append("\(key): no entry point")
                    continue
                }
                programs[key] = CompiledProgram(entry: entry, vertexFunction: vertexFunction, fragmentFunction: fragmentFunction)
            } catch {
                let lines = "\(error)".split(separator: "\n")
                failures.append("\(key): \(lines.first { $0.contains("error:") } ?? lines.first ?? "")")
            }
        }
        for (signature, reason) in manifest.failures.sorted(by: { $0.key < $1.key }) { failures.append("\(signature): \(reason)") }
    }

    var count: Int { programs.count }

    func program(for request: ProgramRequest) -> CompiledProgram? {
        manifest.requests[request.signature].flatMap { programs[$0] }
    }

    func pipeline(_ program: CompiledProgram, blending: Blending, pixelFormat: MTLPixelFormat) throws -> any MTLRenderPipelineState {
        let key = "\(blending.rawValue)-\(pixelFormat.rawValue)"
        if let pipeline = program.pipelines[key] { return pipeline }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = program.vertexFunction
        descriptor.fragmentFunction = program.fragmentFunction
        descriptor.vertexDescriptor = VertexLayout.descriptor(for: program.vertex.attributes)
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        blending.apply(to: descriptor.colorAttachments[0])
        let pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        program.pipelines[key] = pipeline
        return pipeline
    }
}
