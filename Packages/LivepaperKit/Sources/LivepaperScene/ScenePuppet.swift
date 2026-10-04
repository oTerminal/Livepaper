import Foundation
import simd

/// A puppet (`models/*.mdl`, "MDLV0023"): an image layer's mesh, bent by
/// bones that an animation moves. Learned from one sample:
///
///     "MDLV0023\0" u32 flags, u32, u32, material path (text and NUL), zero padding
///     u32 flags, u32 vertex bytes, vertices of 80 bytes:
///         f32 position[3], f32 normal[3], f32 tangent[4], u32 bones[4], f32 weights[4], f32 uv[2]
///     u32 index bytes, u16 triangle-list indices
///     part table, 16-byte records up to the skeleton: (u32 0, u32 first index, u32 index count, u32 part id)
///     "MDLS0004\0" u32 end offset, u32 bone count,
///         per bone: name, u32 flags, i32 parent, u32 matrix bytes (64), f32 local bind matrix[16], u8
///     "MDLA0006\0" u32 end offset, u32 animation count,
///         per animation: u32 id, u32, name, mode ("mirror", …), f32 fps, u32 length in frames,
///         u32, u32 bone count; per bone: u32, u32 bytes, per frame f32 position[3], angles[3], scale[3]
///
/// Positions are pixels from the layer's centre, y up; in the bind pose the
/// mesh lies as the texture does, and the animation moves its parts into place.
public struct ScenePuppet: Sendable {
    public struct Vertex: Sendable {
        public let position: SIMD3<Float>
        public let bones: SIMD4<UInt32>
        public let weights: SIMD4<Float>
        public let uv: SIMD2<Float>
    }

    public struct Bone: Sendable {
        public let parent: Int
        public let bind: simd_float4x4
    }

    public struct Keyframe: Sendable {
        public let position: SIMD3<Float>
        public let angles: SIMD3<Float>
        public let scale: SIMD3<Float>
    }

    public struct Animation: Sendable {
        public let name: String
        /// "mirror" plays forward, then back.
        public let mode: String
        public let framesPerSecond: Float
        public let length: Int
        /// Per bone, per frame.
        public let tracks: [[Keyframe]]
    }

    public static let vertexSize = 80

    public let material: String
    public let vertices: [Vertex]
    public let indices: [UInt16]
    public let bones: [Bone]
    public let animations: [Animation]

    public init(data: Data) throws(SceneReadError) {
        do {
            var reader = ByteReader(data)
            guard try reader.cString(max: 17).hasPrefix("MDLV") else { throw SceneReadError.malformedScene }
            _ = try reader.bytes(12)
            material = try reader.cString()
            // Zero padding, then the vertex block's flags word, which is never zero.
            while reader.remaining >= 4, try Self.peek(reader) == 0 { reader.offset += 1 }
            _ = try reader.u32()
            let vertices = try Self.readVertices(&reader)
            self.vertices = vertices
            indices = try Self.readIndices(&reader, vertexCount: vertices.count)

            // The parts are drawn in file order (the ponytail over the helmet); their table is not needed.
            var skeleton = reader
            guard skeleton.seek(to: "MDLS") else { throw SceneReadError.malformedScene }
            bones = try Self.readBones(&skeleton)
            animations = try Self.readAnimations(after: skeleton)
        } catch let error as SceneReadError {
            throw error
        } catch {
            throw .malformedScene
        }
    }

    private static func peek(_ reader: ByteReader) throws -> UInt8 {
        var copy = reader
        return try copy.u8()
    }

    /// The vertex block after its flags word: its length in bytes, then the vertices.
    private static func readVertices(_ reader: inout ByteReader) throws -> [Vertex] {
        let vertexBytes = try reader.int()
        guard vertexBytes >= 0, vertexBytes % Self.vertexSize == 0 else { throw SceneReadError.malformedScene }
        var vertices: [Vertex] = []
        for _ in 0..<vertexBytes / Self.vertexSize {
            let position = SIMD3(try reader.f32(), try reader.f32(), try reader.f32())
            _ = try reader.bytes(28)  // the normal and the tangent
            let bones = SIMD4(try reader.u32(), try reader.u32(), try reader.u32(), try reader.u32())
            let weights = SIMD4(try reader.f32(), try reader.f32(), try reader.f32(), try reader.f32())
            let uv = SIMD2(try reader.f32(), try reader.f32())
            vertices.append(Vertex(position: position, bones: bones, weights: weights, uv: uv))
        }
        return vertices
    }

    /// The index block: its length in bytes, then the triangle list, every
    /// index one of the `vertexCount` vertices.
    private static func readIndices(_ reader: inout ByteReader, vertexCount: Int) throws -> [UInt16] {
        let indexBytes = try reader.int()
        guard indexBytes >= 0 else { throw SceneReadError.malformedScene }
        var indices: [UInt16] = []
        for _ in 0..<indexBytes / 2 { indices.append(try reader.u16()) }
        guard indices.allSatisfy({ Int($0) < vertexCount }) else { throw SceneReadError.malformedScene }
        return indices
    }

    /// The skeleton, from its "MDLS" tag: each bone's parent and bind matrix.
    private static func readBones(_ skeleton: inout ByteReader) throws -> [Bone] {
        _ = try skeleton.tag()
        _ = try skeleton.u32()
        let boneCount = try skeleton.int()
        guard (0...256).contains(boneCount) else { throw SceneReadError.malformedScene }
        var bones: [Bone] = []
        for _ in 0..<boneCount {
            _ = try skeleton.cString()
            _ = try skeleton.u32()
            let parent = try skeleton.int()
            let size = try skeleton.int()
            guard size >= 64 else { throw SceneReadError.malformedScene }
            var matrix: [Float] = []
            for _ in 0..<16 { matrix.append(try skeleton.f32()) }
            _ = try skeleton.bytes(size - 64)
            _ = try skeleton.u8()
            bones.append(Bone(parent: parent, bind: simd_float4x4(columns: (
                SIMD4(matrix[0], matrix[1], matrix[2], matrix[3]), SIMD4(matrix[4], matrix[5], matrix[6], matrix[7]),
                SIMD4(matrix[8], matrix[9], matrix[10], matrix[11]), SIMD4(matrix[12], matrix[13], matrix[14], matrix[15])
            ))))
        }
        return bones
    }

    private static func readAnimations(after skeleton: ByteReader) throws -> [Animation] {
        var reader = skeleton
        guard reader.seek(to: "MDLA") else { return [] }
        _ = try reader.tag()
        _ = try reader.u32()
        let count = try reader.int()
        guard (0...64).contains(count) else { throw SceneReadError.malformedScene }
        var animations: [Animation] = []
        for _ in 0..<count {
            _ = try reader.bytes(8)
            let name = try reader.cString()
            let mode = try reader.cString()
            let framesPerSecond = try reader.f32()
            let length = try reader.int()
            _ = try reader.u32()
            let trackCount = try reader.int()
            guard (0...256).contains(trackCount) else { throw SceneReadError.malformedScene }
            var tracks: [[Keyframe]] = []
            for _ in 0..<trackCount {
                _ = try reader.u32()
                let bytes = try reader.int()
                guard bytes >= 0 else { throw SceneReadError.malformedScene }
                var frames: [Keyframe] = []
                for _ in 0..<bytes / 36 {
                    frames.append(Keyframe(
                        position: SIMD3(try reader.f32(), try reader.f32(), try reader.f32()),
                        angles: SIMD3(try reader.f32(), try reader.f32(), try reader.f32()),
                        scale: SIMD3(try reader.f32(), try reader.f32(), try reader.f32())
                    ))
                }
                tracks.append(frames)
            }
            animations.append(Animation(name: name, mode: mode, framesPerSecond: framesPerSecond, length: length, tracks: tracks))
        }
        return animations
    }
}
