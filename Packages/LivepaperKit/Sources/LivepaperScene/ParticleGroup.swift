import Foundation
import Metal
import simd

/// A particle object: its system, children that live beside it, and children
/// that burst where its particles die.
final class ParticleGroup {
    final class Part {
        let system: ParticleSystem
        let material: SceneMaterial
        /// Bursts where the first part's particles die.
        let burstsOnDeath: Bool
        let offset: SIMD3<Float>
        /// Vertex buffers taken in turn, so the CPU never writes one the GPU may still read.
        var buffers: [any MTLBuffer] = []
        var nextBuffer = 0
        var floats: [Float] = []

        init(system: ParticleSystem, material: SceneMaterial, burstsOnDeath: Bool, offset: SIMD3<Float>) {
            self.system = system
            self.material = material
            self.burstsOnDeath = burstsOnDeath
            self.offset = offset
        }
    }

    /// Frames in flight at most: the engine asks for a latency of two.
    static let buffersInTurn = 3

    let parts: [Part]

    init(_ object: SceneParticles, in document: SceneDocument) throws(SceneReadError) {
        let files = document.files
        let root = try ParticleDefinition(files: files, file: object.file)
        let material = try document.firstPass(of: root.material)
        let seed = UInt64(truncatingIfNeeded: object.id &* 7919 &+ 17)
        var parts = [Part(
            system: ParticleSystem(root, overrides: object.overrides, values: document.values, seed: seed),
            material: material, burstsOnDeath: false, offset: .zero
        )]
        for (index, child) in root.children.enumerated() {
            guard
                let definition = try? ParticleDefinition(files: files, file: child.file),
                let material = try? document.firstPass(of: definition.material)
            else { continue }
            let bursts = child.type == "eventspawn"
            let system = ParticleSystem(
                definition, overrides: bursts ? [:] : object.overrides, values: document.values, scale: child.scale.x,
                maxCount: child.maxCount, emits: !bursts, seed: seed &+ UInt64(index + 1)
            )
            parts.append(Part(system: system, material: material, burstsOnDeath: bursts, offset: child.origin))
        }
        self.parts = parts
    }

    var unsupported: [String] { parts.flatMap(\.system.unsupported) }

    func advance(to time: Float) {
        let bursting = parts.filter(\.burstsOnDeath)
        parts[0].system.advance(to: time) { parent in
            for part in bursting {
                for position in parent.deaths {
                    for _ in 0..<min(5, part.system.maxCount) { part.system.spawn(at: position) }
                }
            }
        }
        for part in parts.dropFirst() { part.system.advance(to: time) }
    }

    /// The part's vertices in the next buffer of its turn, grown as needed.
    func vertexBuffer(for part: Part, grid: FrameGrid, device: any MTLDevice) -> Mesh? {
        part.system.vertices(into: &part.floats, grid: grid)
        guard !part.floats.isEmpty else { return nil }
        let length = part.floats.count * MemoryLayout<Float>.stride
        if part.buffers.count < Self.buffersInTurn || part.buffers[part.nextBuffer].length < length {
            // Room for half as many again, so that a growing system does not make a buffer every frame.
            guard let buffer = device.makeBuffer(length: length + length / 2, options: .storageModeShared) else { return nil }
            if part.buffers.count < Self.buffersInTurn {
                part.buffers.append(buffer)
                part.nextBuffer = part.buffers.count - 1
            } else {
                part.buffers[part.nextBuffer] = buffer
            }
        }
        let buffer = part.buffers[part.nextBuffer]
        part.nextBuffer = (part.nextBuffer + 1) % Self.buffersInTurn
        part.floats.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            buffer.contents().copyMemory(from: base, byteCount: length)
        }
        return Mesh(vertices: buffer, vertexCount: part.floats.count / 9, indices: nil)
    }
}
