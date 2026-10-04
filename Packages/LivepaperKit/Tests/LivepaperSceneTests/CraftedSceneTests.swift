import CoreGraphics
import Foundation
import Metal
import Testing
@testable import LivepaperScene
import LivepaperTestSupport

/// A scene is someone else's work, and one made to do harm must be refused or
/// drawn without, never crash the extension or stall its render thread, which
/// every surface shares. Each of these would trap or hang without its guard.
struct CraftedSceneTests {
    // MARK: Numbers

    static let floats: [Row<Float, Int>] = [
        Row("a number is cut toward zero", 2.9, 2),
        Row("a negative one too", -2.9, -2),
        Row("not a number is zero", .nan, 0),
        Row("infinity is the largest there is", .infinity, .max),
        Row("and minus infinity the smallest", -.infinity, .min),
        Row("a number too large for an Int is held to the largest", 1e30, .max),
        Row("and one too small to the smallest", -1e30, .min),
    ]

    @Test(arguments: floats)
    func `a float from a scene becomes a whole number without trapping`(row: Row<Float, Int>) {
        #expect(Int(clamping: row.input) == row.expected)
    }

    @Test func `a user property bound to itself, or to one bound back to it, takes the fallback`() {
        let values = SceneValues(project: ["general": ["properties": [
            "loop": ["value": ["user": "loop", "value": 1]],
            "ping": ["value": ["user": "pong", "value": 1]],
            "pong": ["value": ["user": "ping", "value": 1]],
        ]]])

        #expect(values.float(["user": "loop", "value": 2], 7) == 7)
        #expect(values.float(["user": "ping", "value": 2], 7) == 7)
    }

    // MARK: Textures

    @Test func `a texture whose mip claims a size past all memory is refused, not multiplied out`() throws {
        let huge = SyntheticScene.RawImage(width: Int(Int32.max), height: Int(Int32.max), pixels: Data(count: 16))
        let texture = try SceneTexture(data: SyntheticScene.texture([huge], frames: nil, compressed: false))

        #expect(throws: SceneReadError.malformedScene) { try texture.pixels() }
    }

    @Test func `an image stored as a file wider than any texture is refused before it is decoded`() throws {
        let png = try SceneTextureTests.png(width: 16385, height: 1, rgba: [1, 2, 3, 255])
        let raw = SceneTextureTests.raw(width: 1, height: 1, bytesPerPixel: 4, value: 0)
        let data = SceneTextureTests.storingFile(png, in: SyntheticScene.texture([raw], frames: nil, compressed: false))

        #expect(throws: SceneReadError.malformedScene) { try SceneTexture(data: data).pixels() }
    }

    @Test func `a sprite sheet whose picture claims a size past all memory is unreadable`() {
        let huge = SyntheticScene.RawImage(width: Int(Int32.max), height: Int(Int32.max), pixels: Data(count: 16))
        let frames = [0, 1].map { _ in SyntheticScene.Frame(image: 0, seconds: 0.1, x: 0, y: 0, width: 1, height: 1) }

        #expect(throws: SpriteSheetError.unreadable) {
            try SpriteSheet(texture: SyntheticScene.texture([huge], frames: frames, compressed: false))
        }
    }

    // MARK: Particles

    /// A system of at most 50 particles from `emitter`, living five seconds, with `extra` fields.
    static func particles(emitter: String = #""rate": 10"#, extra: String = "", overrides: String = "{}") throws -> ParticleSystem {
        let json = #"""
            {"material": "materials/p.json", "maxcount": 50\#(extra.isEmpty ? "" : ", " + extra),
             "emitter": [{"name": "boxrandom", \#(emitter)}],
             "initializer": [{"name": "lifetimerandom", "min": 5, "max": 5}]}
            """#
        let package = try ScenePackage(data: SyntheticScene.package([.init("particles/p.json", json: json)]))
        let files = SceneFiles(package: package)
        let object = (try JSONSerialization.jsonObject(with: Data(overrides.utf8))) as? [String: Any] ?? [:]
        let definition = try ParticleDefinition(files: files, file: "particles/p.json")
        return ParticleSystem(definition, overrides: object, values: files.values, seed: 1)
    }

    /// Whether `work` ends within `seconds`, run on a thread of its own so that a hang fails the test rather than the run.
    static func finishes(within seconds: Double, _ work: @escaping @Sendable () throws -> Void) -> Bool {
        let done = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            try? work()
            done.signal()
        }
        return done.wait(timeout: .now() + seconds) == .success
    }

    @Test func `an emitter's rate past reason fills the system and goes on, and never stalls a frame`() {
        let counts = Counts()

        let finished = Self.finishes(within: 10) {
            let system = try Self.particles(emitter: #""rate": 1e30"#)
            system.advance(to: 0.1)
            system.advance(to: 0.2)
            counts.record(system.particles.count)
        }

        #expect(finished)
        #expect(counts.values == [50])
    }

    @Test func `a system catches up on a long run's time without stalling`() {
        // Twelve days in, a thirtieth of a second no longer moves a Float's time.
        let counts = Counts()

        let finished = Self.finishes(within: 10) {
            let system = try Self.particles()
            system.advance(to: 1_200_000)
            counts.record(system.particles.count)
        }

        #expect(finished)
        #expect(counts.values.first ?? 0 > 0)
    }

    @Test func `drawn at 30 fps well into a run, a system takes one step a frame, never two and then none`() throws {
        let system = try Self.particles()
        var steps: [Int] = []

        // The scene's time as the drawing gets it: the display link's, a Double, made a Float.
        for frame in 3000...3300 {
            var taken = 0
            system.advance(to: Float(Double(frame) / 30)) { _ in taken += 1 }
            steps.append(taken)
        }

        #expect(Set(steps.dropFirst()) == [1], "steps a frame after the first: \(Set(steps.dropFirst()).sorted())")
    }

    @Test func `counts, control points and sequences that are not numbers or have no end are drawn without`() throws {
        let uncounted = try Self.particles(overrides: #"{"count": "nan"}"#)
        uncounted.advance(to: 1)
        #expect(uncounted.particles.isEmpty)

        let endless = try Self.particles(overrides: #"{"count": "inf"}"#)
        endless.advance(to: 1)
        #expect(endless.maxCount == ParticleDefinition.mostParticles)

        let attracted = try Self.particles(extra: #""operator": [{"name": "controlpointattract", "controlpoint": "nan"}]"#)
        attracted.advance(to: 1)
        #expect(!attracted.particles.isEmpty)

        let sequenced = try Self.particles(extra: #""animationmode": "sequence", "sequencemultiplier": "inf""#)
        sequenced.advance(to: 1)
        var floats: [Float] = []
        sequenced.vertices(into: &floats, grid: FrameGrid(columns: 2, rows: 2, count: 4))
        #expect(floats.count == sequenced.particles.count * 54)
    }

    // MARK: Programs

    @Test func `a uniform array too long to lay out is held to a length that can be`() {
        let layout = UniformLayout.std140([
            .init(type: "vec4", name: "g_Huge", count: Int.max),
            .init(type: "float", name: "g_After", count: nil),
        ])

        #expect(layout.size <= UniformLayout.mostArrayElements * 16 + 32)
        #expect(layout.pack { _ in [1] }.count == layout.size)
    }

    @Test func `an integer uniform given a number past what it holds is held to the most it holds`() {
        let layout = UniformLayout.std140([.init(type: "int", name: "g_Count", count: nil)])

        let bytes = layout.pack { _ in [1e30] }

        #expect(Array(bytes.prefix(4)) == [0xFF, 0xFF, 0xFF, 0x7F])
    }

    @Test func `a vertex attribute past the ones a pipeline has is left out`() {
        let descriptor = VertexLayout.descriptor(for: [
            VertexAttribute(name: "a_Position", type: "vec3", location: 0),
            VertexAttribute(name: "a_Extra", type: "vec2", location: 100),
        ])

        #expect(descriptor.attributes[0].format == .float3)
    }
}

/// Whole numbers seen on another thread.
private final class Counts: @unchecked Sendable {
    private let lock = NSLock()
    private var seen: [Int] = []

    var values: [Int] { lock.withLock { seen } }

    func record(_ value: Int) {
        lock.withLock { seen.append(value) }
    }
}

/// A puppet that a scene carries, posed at any time, however its file sets its rate and bones.
@Suite(.enabled(if: MTLCreateSystemDefaultDevice() != nil))
struct CraftedPuppetTests {
    let device = MTLCreateSystemDefaultDevice()!

    /// The puppet's bytes with the animation's rate, the float after its mode ("loop"), set to `rate`.
    static func puppet(rate: Float) throws -> Data {
        var data = SyntheticScene.puppet(half: 10, frames: 4, step: 2)
        let mode = try #require(data.firstRange(of: Data("loop".utf8) + [0]))
        withUnsafeBytes(of: rate.bitPattern.littleEndian) { data.replaceSubrange(mode.upperBound..<mode.upperBound + 4, with: $0) }
        return data
    }

    @Test(arguments: [Float.infinity, .nan, 1e30])
    func `a puppet whose rate has no end is posed without trapping`(rate: Float) throws {
        let mesh = try PuppetMesh(ScenePuppet(data: Self.puppet(rate: rate)), device: device)

        let pose = mesh.pose(at: 1, halfSize: SIMD2(10, 10))

        #expect(pose.count == PuppetMesh.maxBones * 16)
        #expect(pose.allSatisfy { $0.isFinite })
    }

    @Test func `a puppet posed before its start is posed within its frames`() throws {
        let mesh = try PuppetMesh(ScenePuppet(data: Self.puppet(rate: 10)), device: device)

        let pose = mesh.pose(at: -1.5, halfSize: SIMD2(10, 10))

        #expect(pose.allSatisfy { $0.isFinite })
    }

    @Test func `a vertex on a bone past the ones the shader has is held to the last it has`() throws {
        var data = SyntheticScene.puppet(half: 10, frames: 4, step: 2)
        // The vertex block's length (four vertices of 80 bytes), then the first vertex: 40 bytes before its bones.
        let block = try #require(data.firstRange(of: Data([0x40, 0x01, 0, 0])))
        let bones = block.upperBound + 40
        withUnsafeBytes(of: UInt32(1000).littleEndian) { data.replaceSubrange(bones..<bones + 4, with: $0) }

        let mesh = try PuppetMesh(ScenePuppet(data: data), device: device)

        let first = mesh.mesh.vertices.contents().bindMemory(to: Float.self, capacity: 13)
        #expect(first[5] == Float(PuppetMesh.maxBones - 1))
    }
}
