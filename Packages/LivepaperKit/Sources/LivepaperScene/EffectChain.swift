import Foundation
import Metal
import simd

extension WallpaperEngineScene {
    /// The render targets one effect of a layer can name.
    struct EffectTargets {
        /// The effect's own (`fbos`), by name.
        var named: [String: any MTLTexture]
        /// The picture so far.
        var scene: any MTLTexture
        /// Every target the scene keeps, for another layer's (`_rt_imageLayerComposite_<id>_a`).
        var kept: [String: any MTLTexture]

        func resolve(_ name: String) -> (any MTLTexture)? {
            if let found = named[name] { return found }
            // A scene's pass names a target with a suffix of its own: _rt_FullCompoBuffer1_61_69.
            if let found = named.first(where: { name.hasPrefix($0.key + "_") })?.value { return found }
            if name == "_rt_FullFrameBuffer" { return scene }
            if name.hasPrefix("_rt_imageLayerComposite_") {
                let parts = name.dropFirst("_rt_imageLayerComposite_".count).split(separator: "_")
                if parts.count == 2 { return kept["layer\(parts[0]).\(parts[1])"] }
            }
            return nil
        }
    }

    /// A layer's effects to run: the visible ones, in order, the key the
    /// layer's render targets are kept under, and the picture they start from.
    struct LayerEffects {
        var effects: [SceneEffect]
        var layerKey: String
        var input: any MTLTexture
    }

    /// A layer's effects, in order. Each effect's passes take turns between two
    /// layer-sized targets unless a pass names a target of its own (`fbos`, a
    /// fraction of the size); `bind` puts "previous" or a named target in a
    /// slot; `copy` copies one target to another. Targets outlive the frame, so
    /// effects with history, such as motion blur, keep it. Answers the last output.
    func runEffects(
        _ layer: LayerEffects, scene: any MTLTexture, at time: Float, on commandBuffer: any MTLCommandBuffer
    ) -> any MTLTexture {
        let input = layer.input
        let (width, height) = (input.width, input.height)
        let turns = (input, target("\(layer.layerKey).b", width: width, height: height))
        var current = input
        for (index, effect) in layer.effects.enumerated() {
            var named: [String: any MTLTexture] = [:]
            for declared in effect.targets {
                let divisor = max(1, declared.scale)
                let key = "\(layer.layerKey).e\(index).\(declared.name)"
                named[declared.name] = target(key, width: width / divisor, height: height / divisor)
            }
            let targets = EffectTargets(named: named, scene: scene, kept: self.targets)
            for pass in effect.passes {
                if pass.command == "copy" {
                    if let source = pass.source.flatMap(targets.resolve), let destination = pass.target.flatMap(targets.resolve) {
                        copy(source, to: destination, on: commandBuffer)
                    }
                    continue
                }
                guard let material = pass.material, let program = program(for: pass, material: material, of: effect) else { continue }
                let output: any MTLTexture
                if let name = pass.target {
                    guard let found = targets.resolve(name) else {
                        note("render target \(name) is not declared")
                        continue
                    }
                    output = found
                } else {
                    output = current === turns.0 ? turns.1 : turns.0
                }
                let slots = self.slots(for: pass, program: program, input: current, targets: targets, at: time)
                let draw = MaterialPassDraw(
                    program: program, material: material, blending: Blending(material.blending), target: output, clearing: true,
                    slots: slots
                )
                self.draw(draw, at: time, on: commandBuffer)
                if pass.target == nil { current = output }
            }
        }
        return current
    }

    private func program(for pass: EffectPass, material: SceneMaterial, of effect: SceneEffect) -> CompiledProgram? {
        let bound = ProgramRequest.boundSlots(of: material, binds: pass.binds, in: document.files)
        let request = ProgramRequest(material: material, boundSlots: bound)
        guard let program = programs.program(for: request) else {
            note("effect \(effect.name): no program for \(request.signature)")
            return nil
        }
        return program
    }

    /// A pass's textures: the material's, then its binds, then the input in
    /// slot 0, then any default a sampler declares ("util/white") for a slot still empty.
    private func slots(
        for pass: EffectPass, program: CompiledProgram, input: any MTLTexture, targets: EffectTargets, at time: Float
    ) -> [Int: BoundTexture] {
        var slots: [Int: BoundTexture] = [:]
        func bind(_ name: String, to slot: Int) {
            if name.hasPrefix("_rt_") {
                if let found = targets.resolve(name) {
                    slots[slot] = bound(target: found)
                } else {
                    note("render target \(name) is not found")
                }
            } else if let loaded = textures.texture(named: name) {
                slots[slot] = bound(loaded, at: time)
            }
        }
        for (slot, name) in (pass.material?.textures ?? []).enumerated() {
            if let name { bind(name, to: slot) }
        }
        for binding in pass.binds {
            if binding.name == "previous" {
                slots[binding.slot] = bound(target: input)
            } else if let found = targets.resolve(binding.name) {
                slots[binding.slot] = bound(target: found)
            }
        }
        if slots[0] == nil { slots[0] = bound(target: input) }
        for (slotText, name) in program.entry.samplerDefaults {
            guard let slot = Int(slotText), slots[slot] == nil else { continue }
            bind(name, to: slot)
        }
        return slots
    }
}
