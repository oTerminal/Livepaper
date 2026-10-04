import Foundation
import Metal
import simd

/// A texture in a material's slot, with what `g_TextureNResolution` says of it.
struct BoundTexture {
    let texture: any MTLTexture
    let resolution: SIMD4<Float>
    let sampler: any MTLSamplerState
}

/// One material pass to draw: a translated program, over the quad or `mesh`,
/// into `target`, its uniforms filled from `extra`, then from the values
/// drawing supplies, then from the material's constants, then from the
/// shader's defaults.
struct MaterialPassDraw {
    var program: CompiledProgram
    var material: SceneMaterial?
    var blending: Blending
    var target: any MTLTexture
    /// Clears the target first; otherwise draws over what is there.
    var clearing: Bool
    var transform: simd_float4x4 = matrix_identity_float4x4
    var slots: [Int: BoundTexture]
    var extra: [String: [Float]] = [:]
    var mesh: Mesh?
}

extension WallpaperEngineScene {
    func bound(_ loaded: LoadedTexture, at time: Float) -> BoundTexture {
        let frame = loaded.frame(at: time)
        return BoundTexture(
            texture: frame.texture, resolution: loaded.resolution,
            sampler: textures.sampler(pointFiltered: loaded.isPointFiltered, clamps: loaded.clamps)
        )
    }

    func bound(target: any MTLTexture) -> BoundTexture {
        let size = SIMD4(Float(target.width), Float(target.height), Float(target.width), Float(target.height))
        return BoundTexture(texture: target, resolution: size, sampler: textures.sampler(pointFiltered: false, clamps: true))
    }

    func draw(_ pass: MaterialPassDraw, at time: Float, on commandBuffer: any MTLCommandBuffer) {
        let pipeline: any MTLRenderPipelineState
        do {
            pipeline = try programs.pipeline(pass.program, blending: pass.blending, pixelFormat: pass.target.pixelFormat)
        } catch {
            note("\(pass.program.name) does not link: not drawn")
            return
        }
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = pass.target
        descriptor.colorAttachments[0].loadAction = pass.clearing ? .clear : .load
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.label = pass.program.name
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(pass.mesh?.vertices ?? quad, offset: 0, index: VertexLayout.bufferIndex)
        let value = { (member: UniformLayout.Member) in self.uniformValue(member, of: pass, at: time) }
        setUniforms(pass.program.vertex.uniforms.pack(value), on: encoder, vertex: true)
        setUniforms(pass.program.fragment.uniforms.pack(value), on: encoder, vertex: false)
        let white = bound(textures.white, at: time)
        for binding in pass.program.fragment.samplers.values {
            let texture = pass.slots[binding] ?? white
            encoder.setFragmentTexture(texture.texture, index: binding)
            encoder.setFragmentSamplerState(texture.sampler, index: binding)
        }
        for binding in pass.program.vertex.samplers.values {
            let texture = pass.slots[binding] ?? white
            encoder.setVertexTexture(texture.texture, index: binding)
            encoder.setVertexSamplerState(texture.sampler, index: binding)
        }
        if let mesh = pass.mesh, let indices = mesh.indices {
            encoder.drawIndexedPrimitives(
                type: .triangle, indexCount: indices.count, indexType: .uint16, indexBuffer: indices.buffer, indexBufferOffset: 0
            )
        } else if let mesh = pass.mesh {
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: mesh.vertexCount)
        } else {
            encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }
        encoder.endEncoding()
    }

    private func setUniforms(_ bytes: [UInt8], on encoder: any MTLRenderCommandEncoder, vertex: Bool) {
        if bytes.count <= 4096 {
            if vertex {
                encoder.setVertexBytes(bytes, length: bytes.count, index: 0)
            } else {
                encoder.setFragmentBytes(bytes, length: bytes.count, index: 0)
            }
        } else if let buffer = device.makeBuffer(bytes: bytes, length: bytes.count) {
            if vertex {
                encoder.setVertexBuffer(buffer, offset: 0, index: 0)
            } else {
                encoder.setFragmentBuffer(buffer, offset: 0, index: 0)
            }
        }
    }

    static func floats(_ matrix: simd_float4x4) -> [Float] {
        [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3].flatMap { [$0.x, $0.y, $0.z, $0.w] }
    }

    private func uniformValue(_ member: UniformLayout.Member, of pass: MaterialPassDraw, at time: Float) -> [Float]? {
        if let value = pass.extra[member.name] { return value }
        if let value = suppliedValue(member.name, of: pass, at: time) { return value }
        if let source = pass.program.entry.uniforms[member.name] {
            if let key = source.materialKey, let value = pass.material?.constants[key], let numbers = document.floats(value) {
                return numbers
            }
            if let value = source.defaultValue { return value }
        }
        note("uniform \(member.name) of \(pass.program.name) has no value: zero")
        return nil
    }

    /// The values drawing supplies, by Wallpaper Engine's names, inferred from how the shaders use them.
    private func suppliedValue(_ name: String, of pass: MaterialPassDraw, at time: Float) -> [Float]? {
        switch name {
        case "g_ModelViewProjectionMatrix", "g_EffectModelViewProjectionMatrix":
            return Self.floats(pass.transform)
        case "g_EffectTextureProjectionMatrix", "g_EffectTextureProjectionMatrixInverse":
            return Self.floats(matrix_identity_float4x4)
        case "g_Time":
            return [time]
        case "g_Screen":
            return [Float(width), Float(height), Float(width) / Float(max(height, 1))]
        case "g_ParallaxPosition", "g_PointerPosition", "g_PointerPositionLast":
            // The pointer as the scene follows it, the middle when there is none.
            return [pointer.x, pointer.y]
        default:
            if name.hasPrefix("g_AudioSpectrum") {
                note("audio-reactive uniforms hear silence (\(name))")
                return []
            }
            if name.hasPrefix("g_Texture"), name.hasSuffix("Resolution"),
               let slot = Int(name.dropFirst("g_Texture".count).dropLast("Resolution".count)) {
                let resolution = pass.slots[slot]?.resolution ?? SIMD4(1, 1, 1, 1)
                return [resolution.x, resolution.y, resolution.z, resolution.w]
            }
            return nil
        }
    }
}
