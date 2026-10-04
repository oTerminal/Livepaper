import Foundation
import simd

/// A particle system, simulated on the CPU: the emitters, initialisers,
/// operators and renderers the samples use. What each parameter
/// means is read off the presets' values and not checked against Wallpaper
/// Engine, so the motion is plausible rather than exact.
final class ParticleSystem {
    struct Particle {
        var position: SIMD3<Float>
        var velocity: SIMD3<Float> = .zero
        var age: Float = 0
        var life: Float = 1
        var size: Float = 20
        var colour: SIMD3<Float> = .one
        var alpha: Float = 1
        var rotation: Float = 0
        var spin: Float = 0
        var swayFrequency: Float = 0
        var swayPhase: Float = 0
        var swayScale: Float = 0
        var flickerFrequency: Float = 0
        var flickerDepth: Float = 0
        /// 0 to 1, fixed for its life: its own phase in the noise, and its frame of a sheet.
        var seed: Float = 0
    }

    /// The component names simulated; the rest are logged once as not done.
    static let understood: Set<String> = [
        "sphererandom", "boxrandom", "lifetimerandom", "sizerandom", "colorrandom", "alpharandom", "velocityrandom",
        "rotationrandom", "angularvelocityrandom", "turbulentvelocityrandom", "movement", "alphafade", "alphachange",
        "sizechange", "oscillatealpha", "oscillateposition", "angularmovement", "turbulence", "controlpointattract",
        "sprite", "spritetrail", "ropetrail",
    ]

    let definition: ParticleDefinition
    let maxCount: Int
    private let rateScale: Float
    private let sizeScale: Float
    private let alphaScale: Float
    private let lifeScale: Float
    private let speedScale: Float
    /// The object's colour (`instanceoverride.colorn`), which replaces the preset's random colour.
    private let colour: SIMD3<Float>?
    /// Emits all the time; false for an "eventspawn" child, which only bursts.
    let emits: Bool
    private(set) var particles: [Particle] = []
    /// Where particles died in the last step, for "eventspawn" children.
    private(set) var deaths: [SIMD3<Float>] = []
    private var toEmit: Float = 0
    /// Where the steps have reached; nil before the first.
    private var simulated: Float?
    private var random: SeededRandom
    private let initialSeed: UInt64

    init(
        _ definition: ParticleDefinition, overrides: [String: Any], values: SceneValues, scale: Float = 1, maxCount: Int? = nil,
        emits: Bool = true, seed: UInt64
    ) {
        self.definition = definition
        let asked = Int(clamping: Float(maxCount ?? definition.maxCount) * values.float(overrides["count"], 1))
        self.maxCount = min(max(0, asked), ParticleDefinition.mostParticles)
        rateScale = values.float(overrides["rate"], 1)
        sizeScale = values.float(overrides["size"], 1) * scale
        alphaScale = values.float(overrides["alpha"], 1)
        lifeScale = values.float(overrides["lifetime"], 1)
        speedScale = values.float(overrides["speed"], 1) * scale
        colour = overrides["colorn"] == nil ? nil : values.vector(overrides["colorn"], .one)
        self.emits = emits
        initialSeed = seed | 1
        random = SeededRandom(seed: seed | 1)
    }

    var unsupported: [String] {
        (definition.emitters + definition.initialisers + definition.operators + definition.renderers)
            .map(\.name).filter { !Self.understood.contains($0) }
    }

    private func between(_ low: Float, _ high: Float) -> Float { low + (high - low) * random.next() }

    private func between(_ low: SIMD3<Float>, _ high: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3(between(low.x, high.x), between(low.y, high.y), between(low.z, high.z))
    }

    func spawn(at position: SIMD3<Float>? = nil) {
        guard particles.count < maxCount else { return }
        var particle = Particle(position: position ?? .zero, seed: random.next())
        // The random draws are made in this order, which keeps a scene's particles the same on every run.
        if let emitter = definition.emitters.first { emit(&particle, from: emitter, at: position) }
        initialiseLifeAndLook(&particle)
        initialiseMotion(&particle)
        initialiseOscillation(&particle)
        particles.append(particle)
    }

    /// Where the emitter puts a new particle, unless `position` has placed it
    /// already, and the speed it sends it off at: a box's particles start
    /// anywhere in the box, a sphere's at a random angle and distance, moving away.
    private func emit(_ particle: inout Particle, from emitter: ParticleDefinition.Component, at position: SIMD3<Float>?) {
        let origin = emitter.vector("origin", .zero)
        var direction = SIMD3<Float>.zero
        if emitter.name == "boxrandom" {
            let half = emitter.vector("distancemax", SIMD3(128, 128, 0))
            if position == nil { particle.position = origin + SIMD3(random.next() * 2 - 1, random.next() * 2 - 1, 0) * half }
        } else {
            let directions = emitter.vector("directions", SIMD3(1, 1, 0))
            let angle = random.next() * 2 * .pi
            direction = SIMD3(cos(angle), sin(angle), 0) * directions
            let distance = between(emitter.float("distancemin", 0), emitter.float("distancemax", 256))
            if position == nil { particle.position = origin + direction * distance }
        }
        let speed = between(emitter.float("speedmin", 0), emitter.float("speedmax", 0))
        if speed != 0, simd_length(direction) > 0 { particle.velocity = simd_normalize(direction) * speed }
    }

    /// The initialisers for how long a new particle lives and how it looks:
    /// its life, size, colour and opacity, each scaled by the object's overrides.
    private func initialiseLifeAndLook(_ particle: inout Particle) {
        if let life = definition.initialiser("lifetimerandom") { particle.life = between(life.float("min", 1), life.float("max", 1)) }
        particle.life *= lifeScale
        if let size = definition.initialiser("sizerandom") {
            // An exponent above 1 makes small particles commoner than large ones.
            let skew = pow(random.next(), max(size.float("exponent", 1), 0.01))
            particle.size = size.float("min", 20) + (size.float("max", 20) - size.float("min", 20)) * skew
        }
        particle.size *= sizeScale
        if let colours = definition.initialiser("colorrandom") {
            let low = colours.vector("min", SIMD3(repeating: 255))
            let high = colours.vector("max", SIMD3(repeating: 255))
            particle.colour = (low + (high - low) * random.next()) / 255
        }
        // An object's colour replaces the preset's, as its other overrides scale the preset's values (inferred:
        // A Lonely Winter's sakura, pale pink in the preset and near white on the object, show white in its preview).
        if let colour { particle.colour = colour }
        if let alpha = definition.initialiser("alpharandom") { particle.alpha = between(alpha.float("min", 0), alpha.float("max", 1)) }
        particle.alpha *= alphaScale
    }

    /// The initialisers for how a new particle moves: its velocity and a push
    /// in a random direction, both scaled by the object's speed and kept in
    /// the plane, then its rotation and how fast it spins.
    private func initialiseMotion(_ particle: inout Particle) {
        if let velocity = definition.initialiser("velocityrandom") {
            particle.velocity += between(velocity.vector("min", .zero), velocity.vector("max", .zero))
        }
        if let turbulent = definition.initialiser("turbulentvelocityrandom") {
            let speed = between(turbulent.float("speedmin", 50), turbulent.float("speedmax", 100))
            let angle = random.next() * 2 * .pi
            particle.velocity += SIMD3(cos(angle), sin(angle), 0) * speed
        }
        particle.velocity *= speedScale
        particle.velocity.z = 0
        if let rotation = definition.initialiser("rotationrandom") {
            particle.rotation = between(rotation.vector("min", .zero).z, rotation.vector("max", SIMD3(0, 0, 2 * .pi)).z)
        }
        if let spin = definition.initialiser("angularvelocityrandom") {
            particle.spin = between(spin.vector("min", .zero).z, spin.vector("max", .zero).z)
        }
    }

    /// A new particle's own sway and flicker, drawn from the ranges the
    /// oscillating operators give, and fixed for its life.
    private func initialiseOscillation(_ particle: inout Particle) {
        if let sway = definition.operator("oscillateposition") {
            particle.swayFrequency = between(sway.float("frequencymin", 0), sway.float("frequencymax", 1))
            particle.swayScale = between(sway.float("scalemin", 0), sway.float("scalemax", 10))
            particle.swayPhase = between(sway.float("phasemin", 0), sway.float("phasemax", 2 * .pi))
        }
        if let flicker = definition.operator("oscillatealpha") {
            particle.flickerFrequency = between(flicker.float("frequencymin", 0), flicker.float("frequencymax", 1))
            particle.flickerDepth = between(flicker.float("scalemin", 0), flicker.float("scalemax", 1))
        }
    }

    /// The most particles a second an emitter makes: a whole system's worth each step.
    private static let mostPerSecond = Float(ParticleDefinition.mostParticles) / tick

    private func step(_ seconds: Float) {
        deaths = []
        if emits, let emitter = definition.emitters.first {
            let rate = emitter.float("rate", 5) * rateScale
            toEmit += rate.isNaN ? 0 : min(max(rate, 0), Self.mostPerSecond) * seconds
            // Every particle due is spent, as before, but only those there is room for are made.
            let due = Int(clamping: toEmit.rounded(.down))
            toEmit -= Float(due)
            for _ in 0..<min(due, max(0, maxCount - particles.count)) { spawn() }
        }
        let movement = definition.operator("movement")
        let gravity = movement?.vector("gravity", .zero) ?? .zero
        let drag = movement?.float("drag", 0) ?? 0
        let turbulence = definition.operator("turbulence")
        let spinForce = definition.operator("angularmovement")?.vector("force", .zero).z ?? 0
        // A control point with no flags sits at the system's origin plus its offset; one with flags
        // follows the pointer, which a wallpaper does not have.
        let attract = definition.operator("controlpointattract")
        let point = attract.flatMap { attract in
            definition.controlPoints.first { $0.id == Int(clamping: attract.float("controlpoint", 0)) && $0.flags == 0 }?.offset
        }
        for index in particles.indices {
            var particle = particles[index]
            particle.age += seconds
            if movement != nil {
                particle.velocity += gravity * seconds
                particle.velocity *= max(0, 1 - drag * seconds)
            }
            if let turbulence {
                let scale = turbulence.float("scale", 0.005)
                let speed = turbulence.float("speedmax", 100)
                let noise = SIMD3(
                    sin(particle.position.y * scale * 6.28 + particle.seed * 20 + particle.age),
                    cos(particle.position.x * scale * 6.28 + particle.seed * 13 + particle.age), 0
                )
                particle.velocity += noise * turbulence.vector("mask", SIMD3(1, 1, 0)) * speed * seconds
            }
            if let attract, let point {
                let towards = point - particle.position
                let distance = simd_length(towards)
                if distance > 0.001, distance < attract.float("threshold", 512) {
                    particle.velocity += towards / distance * attract.float("scale", 100) * seconds
                }
            }
            particle.spin += spinForce * seconds
            particle.rotation += particle.spin * seconds
            particle.position += particle.velocity * seconds
            particles[index] = particle
        }
        deaths = particles.filter { $0.age >= $0.life }.map(\.position)
        particles.removeAll { $0.age >= $0.life }
    }

    /// Simulates up to `time`, a thirtieth of a second at a time, counting the
    /// steps from where it last started, so that a time gives the same
    /// particles however it was reached. On first use, when time went back a
    /// step or more, or after a jump, it starts again: from the preset's
    /// warm-up (`starttime`) before the scene's start, or from half a minute
    /// before `time`, which is longer than any particle lives. The steps are
    /// counted rather than timed, since far into a long run a thirtieth of a
    /// second no longer moves a `Float`'s time, and never number more than
    /// that half minute's. `afterStep` sees the system after each step, for
    /// bursts where particles died.
    func advance(to time: Float, afterStep: ((ParticleSystem) -> Void)? = nil) {
        let tick = Self.tick
        var from: Float
        if let simulated, time > simulated - tick, time - simulated <= 5 {
            from = simulated
        } else {
            particles = []
            toEmit = 0
            random = SeededRandom(seed: initialSeed)
            let warmUp = definition.startTime.isNaN ? 0 : definition.startTime
            from = max(-warmUp, time - Self.catchUp)
        }
        // To the nearest step: a frame's time is a step on from the last give or take a Float's
        // rounding, which rounding up would make two steps, then none.
        let steps = min(max(0, Int(clamping: ((time - from) / tick).rounded())), Self.mostSteps)
        for _ in 0..<steps {
            step(tick)
            afterStep?(self)
        }
        from += Float(steps) * tick
        simulated = from
    }

    /// The step, whatever the rate the scene is drawn at.
    private static let tick: Float = 1 / 30
    /// Half a minute, longer than any particle lives: the most simulated to catch up.
    private static let catchUp: Float = 30
    private static let mostSteps = Int((catchUp / tick).rounded()) + 1
}

/// xorshift64: the same particles on every run of a scene.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x2545_F491_4F6C_DD1D : seed
    }

    /// 0 up to 1.
    mutating func next() -> Float {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return Float(state >> 40) / Float(1 << 24)
    }
}
