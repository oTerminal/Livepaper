import Foundation
import Metal
import simd

/// Drawing's own passes, in plain Metal rather than a scene's materials:
/// copying a layer onto the scene, putting the scene into the surface's
/// drawable, and the scene-wide bloom. Written from scratch.
final class BasePasses {
    struct Parameters {
        var transform: simd_float4x4
        /// The part of the source drawn: origin and size, in UV.
        var rect: SIMD4<Float>
        var colour: SIMD4<Float>
        /// x: the bloom's threshold; zw: a blur's step, in UV.
        var extra: SIMD4<Float>

        static func copy(rect: SIMD4<Float> = SIMD4(0, 0, 1, 1), colour: SIMD4<Float> = .one, extra: SIMD4<Float> = .zero) -> Parameters {
            Parameters(transform: matrix_identity_float4x4, rect: rect, colour: colour, extra: extra)
        }
    }

    /// One pass: which of the fragments, over what is in the target or not, blended how.
    struct Pass {
        var fragment = Fragment.textured
        var load = MTLLoadAction.load
        var blending: Blending
        var parameters: Parameters
    }

    private static let source = """
        #include <metal_stdlib>
        using namespace metal;
        struct Corner { float4 position [[position]]; float2 uv; };
        struct Parameters { float4x4 transform; float4 rect; float4 colour; float4 extra; };

        // A quad as a strip of four, uv (0, 0) at the top left, as in Metal and Direct3D.
        vertex Corner base_quad(uint index [[vertex_id]], constant Parameters &p [[buffer(0)]]) {
            float2 corner = float2(index & 1, index >> 1);
            Corner out;
            out.position = p.transform * float4(corner.x * 2 - 1, 1 - corner.y * 2, 0, 1);
            out.uv = p.rect.xy + corner * p.rect.zw;
            return out;
        }

        fragment float4 base_textured(Corner in [[stage_in]], constant Parameters &p [[buffer(0)]],
                                      texture2d<float> source [[texture(0)]], sampler linear [[sampler(0)]]) {
            return source.sample(linear, in.uv) * p.colour;
        }

        // The bloom's bright pass: what is above the threshold, eased in.
        fragment float4 base_bright(Corner in [[stage_in]], constant Parameters &p [[buffer(0)]],
                                    texture2d<float> source [[texture(0)]], sampler linear [[sampler(0)]]) {
            float3 colour = source.sample(linear, in.uv).rgb;
            float level = max(colour.r, max(colour.g, colour.b));
            float kept = max(0.0, level - p.extra.x) / max(level, 1e-4);
            return float4(colour * kept, 1);
        }

        // Nine taps along extra.zw, binomial weights.
        fragment float4 base_blur(Corner in [[stage_in]], constant Parameters &p [[buffer(0)]],
                                  texture2d<float> source [[texture(0)]], sampler linear [[sampler(0)]]) {
            const float weights[5] = { 70.0, 56.0, 28.0, 8.0, 1.0 };
            float4 sum = source.sample(linear, in.uv) * weights[0];
            for (int step = 1; step < 5; step++) {
                float2 offset = p.extra.zw * step;
                sum += (source.sample(linear, in.uv + offset) + source.sample(linear, in.uv - offset)) * weights[step];
            }
            return sum / 256.0;
        }
        """

    private let device: any MTLDevice
    private let library: any MTLLibrary
    /// Linear, clamped at the edges: every one of these passes samples so.
    private let linear: any MTLSamplerState
    private var pipelines: [String: any MTLRenderPipelineState] = [:]

    init(device: any MTLDevice) throws {
        self.device = device
        library = try device.makeLibrary(source: Self.source, options: nil)
        let sampling = MTLSamplerDescriptor()
        sampling.minFilter = .linear
        sampling.magFilter = .linear
        sampling.sAddressMode = .clampToEdge
        sampling.tAddressMode = .clampToEdge
        guard let linear = device.makeSamplerState(descriptor: sampling) else { throw SceneReadError.malformedScene }
        self.linear = linear
    }

    enum Fragment: String {
        case textured = "base_textured"
        case bright = "base_bright"
        case blur = "base_blur"
    }

    private func pipeline(_ fragment: Fragment, blending: Blending, pixelFormat: MTLPixelFormat) -> (any MTLRenderPipelineState)? {
        let key = "\(fragment.rawValue)-\(blending.rawValue)-\(pixelFormat.rawValue)"
        if let pipeline = pipelines[key] { return pipeline }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "base_quad")
        descriptor.fragmentFunction = library.makeFunction(name: fragment.rawValue)
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        blending.apply(to: descriptor.colorAttachments[0])
        let pipeline = try? device.makeRenderPipelineState(descriptor: descriptor)
        pipelines[key] = pipeline
        return pipeline
    }

    /// Draws `source` (the part `pass.parameters.rect` says) onto `target`, through `pass.parameters.transform`.
    func draw(_ source: any MTLTexture, into target: any MTLTexture, on commandBuffer: any MTLCommandBuffer, _ pass: Pass) {
        guard let pipeline = pipeline(pass.fragment, blending: pass.blending, pixelFormat: target.pixelFormat) else { return }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = target
        descriptor.colorAttachments[0].loadAction = pass.load
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.label = pass.fragment.rawValue
        encoder.setRenderPipelineState(pipeline)
        var parameters = pass.parameters
        encoder.setVertexBytes(&parameters, length: MemoryLayout<Parameters>.stride, index: 0)
        encoder.setFragmentBytes(&parameters, length: MemoryLayout<Parameters>.stride, index: 0)
        encoder.setFragmentTexture(source, index: 0)
        encoder.setFragmentSamplerState(linear, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()
    }
}
