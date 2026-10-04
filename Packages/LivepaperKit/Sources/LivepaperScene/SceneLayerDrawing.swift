import Foundation
import Metal
import simd

// A scene's objects drawn onto the picture so far: image layers with or without
// effects, Wallpaper Engine's own fullscreen, compose and solid layers,
// particles, and the scene's bloom.

extension WallpaperEngineScene {
    func drawImageLayer(_ layer: SceneLayer, at time: Float, into scene: any MTLTexture, on commandBuffer: any MTLCommandBuffer) {
        let material = layer.material ?? SceneMaterial(shader: "genericimage2", blending: "translucent")
        guard let texture = texture(of: layer, material: material) else { return }
        guard let request = ProgramRequest.layer(layer), let program = programs.program(for: request) else {
            note("layer \(layer.name): no program for \(ProgramRequest.layer(layer)?.signature ?? material.shader)")
            return
        }
        var size = layer.size
        if size.x == 0 || size.y == 0 { size = SIMD2(texture.resolution.z, texture.resolution.w) }
        let frame = texture.frame(at: time)
        let tint = layer.kind == .solid ? layer.colour : layer.colour * layer.brightness
        let base = BoundTexture(
            texture: frame.texture, resolution: texture.resolution,
            sampler: textures.sampler(pointFiltered: texture.isPointFiltered, clamps: texture.clamps)
        )
        let puppet = puppets[layer.id]
        let effects = layer.effects.filter(\.isVisible)
        var transform = layer.transform
        transform.origin += parallaxOffset(transform)
        let placement = modelViewProjection(transform, halfSize: size / 2)
        var extra: [String: [Float]] = ["g_FrameRect": [frame.rect.x, frame.rect.y, frame.rect.z, frame.rect.w]]
        if let puppet { extra["g_Bones"] = puppet.pose(at: time, halfSize: size / 2) }
        var pass = MaterialPassDraw(
            program: program, material: material, blending: Blending(material.blending), target: scene, clearing: false,
            transform: placement, slots: [0: base], extra: extra, mesh: puppet?.mesh
        )
        guard !effects.isEmpty else {
            pass.extra["g_Color4"] = [tint.x, tint.y, tint.z, layer.alpha]
            draw(pass, at: time, on: commandBuffer)
            return
        }
        // Effects run in the layer's own space, at the size it covers on the output.
        // Sizes and scales come from the scene, so their product can be anything a Float holds; `target` bounds it.
        let width = Int(clamping: (abs(size.x * layer.transform.scale.x) * pixelsPerUnit).rounded())
        let height = Int(clamping: (abs(size.y * layer.transform.scale.y) * pixelsPerUnit).rounded())
        let key = "layer\(layer.id)"
        pass.target = target("\(key).a", width: width, height: height)
        pass.clearing = true
        pass.transform = matrix_identity_float4x4
        pass.extra["g_Color4"] = [tint.x, tint.y, tint.z, 1]
        // A puppet's parts overlap, so they blend; a plain image replaces.
        pass.blending = puppet == nil ? .normal : .translucent
        draw(pass, at: time, on: commandBuffer)
        let run = LayerEffects(effects: effects, layerKey: key, input: pass.target)
        let result = runEffects(run, scene: scene, at: time, on: commandBuffer)
        let compositing = Compositing(transform: placement, blending: Blending(material.blending), alpha: layer.alpha)
        composite(result, into: scene, compositing, on: commandBuffer)
    }

    /// The texture an image layer draws: white for a solid layer, otherwise
    /// its material's first. Nil, and noted, when it has none.
    private func texture(of layer: SceneLayer, material: SceneMaterial) -> LoadedTexture? {
        if layer.kind == .solid { return textures.white }
        if let name = material.textures.first ?? nil, let loaded = textures.texture(named: name) { return loaded }
        note("layer \(layer.name) has no texture")
        return nil
    }

    /// Effects over everything drawn so far.
    func drawFullscreenLayer(_ layer: SceneLayer, at time: Float, into scene: any MTLTexture, on commandBuffer: any MTLCommandBuffer) {
        let effects = layer.effects.filter(\.isVisible)
        guard !effects.isEmpty else { return }
        let key = "layer\(layer.id)"
        let own = target("\(key).a", width: scene.width, height: scene.height)
        copy(scene, to: own, on: commandBuffer)
        let result = runEffects(LayerEffects(effects: effects, layerKey: key, input: own), scene: scene, at: time, on: commandBuffer)
        let compositing = Compositing(transform: matrix_identity_float4x4, blending: .normal, alpha: layer.alpha)
        composite(result, into: scene, compositing, on: commandBuffer)
    }

    /// Effects over what is behind the layer's rectangle.
    func drawComposeLayer(_ layer: SceneLayer, at time: Float, into scene: any MTLTexture, on commandBuffer: any MTLCommandBuffer) {
        let effects = layer.effects.filter(\.isVisible)
        guard !effects.isEmpty, layer.size.x > 0, layer.size.y > 0 else { return }
        let placement = modelViewProjection(layer.transform, halfSize: layer.size / 2)
        // The layer's rectangle in the scene's UV; the samples turn none of them.
        let topLeft = placement * SIMD4<Float>(-1, 1, 0, 1)
        let bottomRight = placement * SIMD4<Float>(1, -1, 0, 1)
        let (left, top) = ((topLeft.x + 1) / 2, (1 - topLeft.y) / 2)
        let (right, bottom) = ((bottomRight.x + 1) / 2, (1 - bottomRight.y) / 2)
        let key = "layer\(layer.id)"
        let own = target(
            "\(key).a", width: Int(clamping: (abs(right - left) * Float(scene.width)).rounded()),
            height: Int(clamping: (abs(bottom - top) * Float(scene.height)).rounded())
        )
        let behind = BasePasses.Parameters.copy(rect: SIMD4(left, top, right - left, bottom - top))
        passes.draw(scene, into: own, on: commandBuffer, .init(load: .clear, blending: .normal, parameters: behind))
        let result = runEffects(LayerEffects(effects: effects, layerKey: key, input: own), scene: scene, at: time, on: commandBuffer)
        let compositing = Compositing(transform: placement, blending: .translucent, alpha: layer.alpha)
        composite(result, into: scene, compositing, on: commandBuffer)
    }

    /// How a layer's effects' result goes onto the scene: through the layer's
    /// placement, blended as the layer is, at the layer's opacity.
    private struct Compositing {
        var transform: simd_float4x4
        var blending: Blending
        var alpha: Float
    }

    private func composite(
        _ texture: any MTLTexture, into scene: any MTLTexture, _ compositing: Compositing, on commandBuffer: any MTLCommandBuffer
    ) {
        let parameters = BasePasses.Parameters(
            transform: compositing.transform, rect: SIMD4(0, 0, 1, 1), colour: SIMD4(1, 1, 1, compositing.alpha), extra: .zero
        )
        passes.draw(texture, into: scene, on: commandBuffer, .init(blending: compositing.blending, parameters: parameters))
    }

    func drawParticles(
        _ object: SceneParticles, index: Int, at time: Float, into scene: any MTLTexture, on commandBuffer: any MTLCommandBuffer
    ) {
        guard let group = particleGroups[index] else { return }
        group.advance(to: time)
        for part in group.parts {
            let texture = (part.material.textures.first ?? nil).flatMap { textures.texture(named: $0) } ?? textures.white
            guard let mesh = group.vertexBuffer(for: part, grid: texture.grid, device: device) else { continue }
            let request = ProgramRequest(material: part.material, boundSlots: [0])
            guard let program = programs.program(for: request) else {
                note("particles \(object.file): no program for \(request.signature)")
                continue
            }
            var transform = object.transform
            transform.origin += part.offset + parallaxOffset(transform)
            let pass = MaterialPassDraw(
                program: program, material: part.material, blending: Blending(part.material.blending), target: scene, clearing: false,
                transform: modelViewProjection(transform, halfSize: SIMD2(1, 1)), slots: [0: bound(texture, at: time)], mesh: mesh
            )
            draw(pass, at: time, on: commandBuffer)
        }
    }

    /// The scene's bloom (`general.bloom`): a bright pass at a quarter of the size, blurred, added back.
    func drawBloom(into scene: any MTLTexture, on commandBuffer: any MTLCommandBuffer) {
        guard document.bool(document.general["bloom"], false) else { return }
        let strength = document.float(document.general["bloomstrength"], 2)
        let threshold = document.float(document.general["bloomthreshold"], 0.65)
        let (width, height) = (max(1, scene.width / 4), max(1, scene.height / 4))
        let bright = target("bloom.a", width: width, height: height)
        let across = target("bloom.b", width: width, height: height)
        passes.draw(
            scene, into: bright, on: commandBuffer,
            .init(fragment: .bright, load: .dontCare, blending: .normal, parameters: .copy(extra: SIMD4(threshold, 0, 0, 0)))
        )
        for _ in 0..<2 {
            let sideways = BasePasses.Parameters.copy(extra: SIMD4(0, 0, 1 / Float(width), 0))
            let upwards = BasePasses.Parameters.copy(extra: SIMD4(0, 0, 0, 1 / Float(height)))
            passes.draw(
                bright, into: across, on: commandBuffer, .init(fragment: .blur, load: .dontCare, blending: .normal, parameters: sideways)
            )
            passes.draw(
                across, into: bright, on: commandBuffer, .init(fragment: .blur, load: .dontCare, blending: .normal, parameters: upwards)
            )
        }
        passes.draw(
            bright, into: scene, on: commandBuffer, .init(blending: .additive, parameters: .copy(colour: SIMD4(1, 1, 1, strength / 2)))
        )
    }
}
