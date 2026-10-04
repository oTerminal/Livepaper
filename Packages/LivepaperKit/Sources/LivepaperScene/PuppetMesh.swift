import Foundation
import Metal
import simd

/// Vertices other than the quad: particles (triangles) or a puppet's mesh (indexed triangles).
struct Mesh {
    let vertices: any MTLBuffer
    let vertexCount: Int
    let indices: (buffer: any MTLBuffer, count: Int)?
}

/// A puppet on the GPU: its mesh, and its bones posed at a time. Linear
/// skinning, up to 32 bones, in our `genericimage` material's `SKINNING`.
final class PuppetMesh {
    static let maxBones = 32
    let puppet: ScenePuppet
    let mesh: Mesh
    private let inverseBind: [simd_float4x4]

    init(_ puppet: ScenePuppet, device: any MTLDevice) throws(SceneReadError) {
        guard puppet.bones.count <= Self.maxBones, !puppet.indices.isEmpty else { throw .malformedScene }
        self.puppet = puppet
        // Position, UV, bone indices, bone weights (`VertexLayout.skinnedStride`).
        var floats: [Float] = []
        floats.reserveCapacity(puppet.vertices.count * 13)
        // A bone past the shader's last would be read from past the end of `g_Bones`.
        let lastBone = UInt32(Self.maxBones - 1)
        for vertex in puppet.vertices {
            let bones = SIMD4<Float>(pointwiseMin(vertex.bones, SIMD4(repeating: lastBone)))
            floats += [vertex.position.x, vertex.position.y, vertex.position.z, vertex.uv.x, vertex.uv.y]
            floats += [bones.x, bones.y, bones.z, bones.w]
            floats += [vertex.weights.x, vertex.weights.y, vertex.weights.z, vertex.weights.w]
        }
        // The parts are drawn in the file's order: in the one sample the last part, the ponytail, lies over the helmet.
        guard
            let vertices = device.makeBuffer(bytes: floats, length: max(4, floats.count * 4)),
            let indices = device.makeBuffer(bytes: puppet.indices, length: max(2, puppet.indices.count * 2))
        else { throw .malformedScene }
        mesh = Mesh(vertices: vertices, vertexCount: puppet.vertices.count, indices: (indices, puppet.indices.count))
        inverseBind = Self.world(puppet.bones.map(\.bind), parents: puppet.bones.map(\.parent)).map(\.inverse)
    }

    private static func world(_ local: [simd_float4x4], parents: [Int]) -> [simd_float4x4] {
        var world = local
        for index in world.indices where parents[index] >= 0 && parents[index] < index {
            world[index] = world[parents[index]] * local[index]
        }
        return world
    }

    /// The bone matrices for `g_Bones` at `time`, taking the mesh's pixels to the layer's unit quad.
    func pose(at time: Float, halfSize: SIMD2<Float>) -> [Float] {
        var local = puppet.bones.map(\.bind)
        // A rate from the file that has no end is no animation.
        if let animation = puppet.animations.first, animation.length > 0,
           animation.framesPerSecond.isFinite, animation.framesPerSecond > 0 {
            var frame = time * animation.framesPerSecond
            let length = Float(animation.length)
            let period = animation.mode == "mirror" ? 2 * length : length
            frame = frame.truncatingRemainder(dividingBy: period)
            // Before the start, the animation is where it would have been had it always played.
            if frame < 0 { frame += period }
            if animation.mode == "mirror", frame > length { frame = 2 * length - frame }
            for (bone, track) in animation.tracks.enumerated() where bone < local.count && !track.isEmpty {
                let first = min(max(Int(clamping: frame), 0), track.count - 1)
                let second = min(track.count - 1, first + 1)
                let between = frame - Float(first)
                let (from, to) = (track[first], track[second])
                let position = from.position + (to.position - from.position) * between
                let angle = from.angles.z + (to.angles.z - from.angles.z) * between
                let scale = from.scale + (to.scale - from.scale) * between
                let (cosine, sine) = (cos(angle), sin(angle))
                let rotation = simd_float4x4(columns: (
                    SIMD4(cosine, sine, 0, 0), SIMD4(-sine, cosine, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)
                ))
                var matrix = rotation * simd_float4x4(diagonal: SIMD4(scale.x, scale.y, 1, 1))
                matrix.columns.3 = SIMD4(position.x, position.y, position.z, 1)
                local[bone] = matrix
            }
        }
        let world = Self.world(local, parents: puppet.bones.map(\.parent))
        let toUnit = simd_float4x4(diagonal: SIMD4(1 / max(halfSize.x, 1e-3), 1 / max(halfSize.y, 1e-3), 1, 1))
        var floats: [Float] = []
        floats.reserveCapacity(Self.maxBones * 16)
        for bone in 0..<Self.maxBones {
            let matrix = bone < world.count ? toUnit * world[bone] * inverseBind[bone] : matrix_identity_float4x4
            floats += [matrix.columns.0, matrix.columns.1, matrix.columns.2, matrix.columns.3].flatMap { [$0.x, $0.y, $0.z, $0.w] }
        }
        return floats
    }
}
