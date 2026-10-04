import Foundation
import simd

extension ParticleSystem {
    /// Two triangles per particle, in the system's own space: position (xyz),
    /// UV, colour (rgba). `grid` is the texture's sheet of frames.
    func vertices(into floats: inout [Float], grid: FrameGrid) {
        floats.removeAll(keepingCapacity: true)
        floats.reserveCapacity(particles.count * 54)
        let style = ParticleVertexStyle(definition, grid: grid)
        for particle in particles {
            let through = particle.age / max(particle.life, 1e-4)
            let alpha = style.alpha(of: particle, through: through)
            let size = style.size(of: particle, through: through)
            let position = style.position(of: particle)
            let colour = particle.colour
            for (offset, uv) in style.corners(of: particle, size: size, through: through) {
                floats += [position.x + offset.x, position.y + offset.y, 0, uv.x, uv.y, colour.x, colour.y, colour.z, max(0, alpha)]
            }
        }
    }
}

/// What turning a system's particles into vertices reads off its definition
/// once a frame rather than once a particle: how they fade, grow and sway,
/// whether they are drawn as trails, and the texture's sheet of frames.
private struct ParticleVertexStyle {
    let fade: ParticleDefinition.Component?
    let fadeIn: Float
    let fadeOut: Float
    let alphaChange: ParticleDefinition.Component?
    let sizeChange: ParticleDefinition.Component?
    let swayMask: SIMD3<Float>
    let trail: ParticleDefinition.Component?
    let grid: FrameGrid
    /// How many frames the sheet has, at least one.
    let frames: Int
    /// Plays the frames in turn over a particle's life, rather than giving each particle one.
    let sequence: Bool
    let sequenceMultiplier: Float
    /// One frame's size, in UV.
    let frameSize: SIMD2<Float>

    init(_ definition: ParticleDefinition, grid: FrameGrid) {
        let fade = definition.operator("alphafade")
        self.fade = fade
        fadeIn = fade?.float("fadeintime", 0.5) ?? 0
        fadeOut = fade?.float("fadeouttime", 0.5) ?? 1
        alphaChange = definition.operator("alphachange")
        sizeChange = definition.operator("sizechange")
        swayMask = definition.operator("oscillateposition")?.vector("mask", SIMD3(1, 1, 0)) ?? .zero
        trail = definition.renderers.first { $0.name == "spritetrail" || $0.name == "ropetrail" }
        self.grid = grid
        frames = max(1, min(grid.count, grid.columns * grid.rows))
        sequence = definition.animationMode == "sequence"
        sequenceMultiplier = definition.sequenceMultiplier
        frameSize = SIMD2(1 / Float(max(grid.columns, 1)), 1 / Float(max(grid.rows, 1)))
    }

    /// A particle's opacity `through` its life (0 to 1): faded in and out,
    /// ramped when the system's opacity changes, and flickering.
    func alpha(of particle: ParticleSystem.Particle, through: Float) -> Float {
        var alpha = particle.alpha
        if fade != nil {
            if through < fadeIn { alpha *= through / max(fadeIn, 1e-4) }
            if through > fadeOut { alpha *= max(0, (1 - through) / max(1 - fadeOut, 1e-4)) }
        }
        if let change = alphaChange { alpha *= Self.ramp(change, through) }
        if particle.flickerFrequency > 0 {
            let wave = 0.5 + 0.5 * sin(particle.age * particle.flickerFrequency * 2 * .pi + particle.seed * 6.28)
            alpha *= 1 - particle.flickerDepth * wave
        }
        return alpha
    }

    /// A particle's size `through` its life, ramped when the system's size changes.
    func size(of particle: ParticleSystem.Particle, through: Float) -> Float {
        var size = particle.size
        if let change = sizeChange { size *= Self.ramp(change, through) }
        return size
    }

    /// Where a particle is drawn: where it is, moved by its sway.
    func position(of particle: ParticleSystem.Particle) -> SIMD3<Float> {
        var position = particle.position
        if particle.swayScale > 0 {
            let phase = particle.age * particle.swayFrequency * 2 * .pi + particle.swayPhase
            position += swayMask * SIMD3(sin(phase), cos(phase), 0) * particle.swayScale
        }
        return position
    }

    /// A particle's two triangles: each corner's offset from where it is
    /// drawn, and its UV in the particle's frame of the sheet.
    func corners(of particle: ParticleSystem.Particle, size: Float, through: Float) -> [(offset: SIMD2<Float>, uv: SIMD2<Float>)] {
        let (across, along) = axes(of: particle, size: size)
        let origin = frameOrigin(of: particle, through: through)
        let right = origin + SIMD2(frameSize.x, 0)
        let below = origin + SIMD2(0, frameSize.y)
        return [
            (-across + along, origin), (across + along, right), (-across - along, below),
            (across + along, right), (across - along, origin + frameSize), (-across - along, below),
        ]
    }

    /// Half a particle's quad each way, across it and along it. A sprite is a
    /// square turned by its rotation; a trail is stretched along its velocity.
    private func axes(of particle: ParticleSystem.Particle, size: Float) -> (across: SIMD2<Float>, along: SIMD2<Float>) {
        var across = SIMD2<Float>(cos(particle.rotation), sin(particle.rotation)) * size / 2
        var along = SIMD2<Float>(-sin(particle.rotation), cos(particle.rotation)) * size / 2
        if let trail {
            let velocity = SIMD2(particle.velocity.x, particle.velocity.y)
            let speed = simd_length(velocity)
            if speed > 0.001 {
                let length = min(speed * trail.float("length", 0.05) * 100, trail.float("maxlength", 1000))
                along = velocity / speed * max(size, length) / 2
                across = SIMD2(-along.y, along.x) / max(simd_length(along), 1e-4) * size / 2
            }
        }
        return (across, along)
    }

    /// The top left of a particle's frame of the sheet, in UV: the frames in
    /// turn over its life for a sequence, otherwise the one its seed picks.
    private func frameOrigin(of particle: ParticleSystem.Particle, through: Float) -> SIMD2<Float> {
        // A multiplier from the file can be anything a Float holds; the frame stays one of the sheet's.
        let frame = sequence
            ? (Int(clamping: through * max(sequenceMultiplier, 1) * Float(frames)) % frames + frames) % frames
            : min(frames - 1, Int(particle.seed * Float(frames)))
        return SIMD2(Float(frame % max(grid.columns, 1)), Float(frame / max(grid.columns, 1))) * frameSize
    }

    /// An operator's value from `startvalue` to `endvalue` between `starttime` and `endtime` of a life.
    private static func ramp(_ change: ParticleDefinition.Component, _ through: Float) -> Float {
        let (start, end) = (change.float("starttime", 0), change.float("endtime", 1))
        let along = min(1, max(0, (through - start) / max(end - start, 1e-4)))
        let (from, to) = (change.float("startvalue", 1), change.float("endvalue", 0))
        return from + (to - from) * along
    }
}
