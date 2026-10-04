import Foundation
import Testing
import LivepaperScene

/// The std140 block the translator gives a stage's loose uniforms, and the
/// bytes drawing fills it with. The offsets are std140's, which is what
/// SPIRV-Cross lays the Metal struct out to.
struct UniformLayoutTests {
    struct Laid: Sendable {
        var offsets: [Int]
        var strides: [Int]
        var size: Int
    }

    /// The block for declarations written as "vec3 g_Colour" or "mat4 g_Bones[4]".
    static func layout(_ declarations: [String]) -> UniformLayout {
        UniformLayout.std140(declarations.map { text in
            let parts = text.split(separator: " ").map(String.init)
            guard let open = parts[1].firstIndex(of: "[") else {
                return UniformLayout.Declaration(type: parts[0], name: parts[1], count: nil)
            }
            let count = Int(parts[1][parts[1].index(after: open)...].dropLast())
            return UniformLayout.Declaration(type: parts[0], name: String(parts[1][..<open]), count: count)
        })
    }

    static let layouts: [Row<[String], Laid>] = [
        Row("nothing is one empty row of 16 bytes", [], Laid(offsets: [], strides: [], size: 16)),
        Row("floats pack four to a row", ["float a", "float b", "float c"], Laid(offsets: [0, 4, 8], strides: [4, 4, 4], size: 16)),
        Row("a vec2 aligns to 8", ["float a", "vec2 b"], Laid(offsets: [0, 8], strides: [4, 8], size: 16)),
        Row("a vec3 aligns to 16", ["float a", "vec3 b"], Laid(offsets: [0, 16], strides: [4, 12], size: 32)),
        Row("a float fits in a vec3's last four bytes", ["vec3 a", "float b"], Laid(offsets: [0, 12], strides: [12, 4], size: 16)),
        Row("a vec4 aligns to 16", ["vec2 a", "vec4 b"], Laid(offsets: [0, 16], strides: [8, 16], size: 32)),
        Row(
            "a mat4 is 64 bytes on rows of its own",
            ["float a", "mat4 b", "float c"],
            Laid(offsets: [0, 16, 80], strides: [4, 64, 4], size: 96)
        ),
        Row("a mat3 is three padded columns", ["mat3 a", "float b"], Laid(offsets: [0, 48], strides: [48, 4], size: 64)),
        Row(
            "an array of floats has a 16-byte stride",
            ["float a", "float b[3]", "float c"],
            Laid(offsets: [0, 16, 64], strides: [4, 16, 4], size: 80)
        ),
        Row("an array of vec2 too", ["vec2 a[2]", "vec2 b"], Laid(offsets: [0, 32], strides: [16, 8], size: 48)),
        Row("an array of mat4 is 64 each", ["mat4 a[2]", "vec4 b"], Laid(offsets: [0, 128], strides: [64, 16], size: 144)),
        Row(
            "ints are laid out as floats",
            ["int a", "ivec2 b", "ivec3 c", "ivec4 d"],
            Laid(offsets: [0, 8, 16, 32], strides: [4, 8, 12, 16], size: 48)
        ),
    ]

    @Test(arguments: layouts)
    func `members are laid out as std140 lays them`(row: Row<[String], Laid>) {
        let layout = Self.layout(row.input)

        #expect(layout.members.map(\.offset) == row.expected.offsets)
        #expect(layout.members.map(\.stride) == row.expected.strides)
        #expect(layout.size == row.expected.size)
        #expect(layout.members.map { "\($0.type) \($0.name)\($0.arrayCount.map { "[\($0)]" } ?? "")" } == row.input)
    }

    // MARK: Packing

    struct Packing: Sendable {
        var declarations: [String]
        var values: [String: [Float]]
    }

    /// The block's bytes read back as 32-bit floats, or as ints where `integers` says so.
    static func words(_ bytes: [UInt8], integers: Set<Int> = []) -> [Float] {
        stride(from: 0, to: bytes.count, by: 4).map { offset in
            let bits = (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * UInt32($1)) }
            return integers.contains(offset / 4) ? Float(Int32(bitPattern: bits)) : Float(bitPattern: bits)
        }
    }

    static let packings: [Row<Packing, [Float]>] = [
        Row("a float", Packing(declarations: ["float a"], values: ["a": [0.5]]), [0.5, 0, 0, 0]),
        Row("a vec2 after a float", Packing(declarations: ["float a", "vec2 b"], values: ["a": [1], "b": [2, 3]]), [1, 0, 2, 3]),
        Row(
            "a vec3 on its own row",
            Packing(declarations: ["float a", "vec3 b"], values: ["a": [1], "b": [2, 3, 4]]),
            [1, 0, 0, 0, 2, 3, 4, 0]
        ),
        Row("one number fills a vector", Packing(declarations: ["vec4 a"], values: ["a": [7]]), [7, 7, 7, 7]),
        Row("a short list leaves the rest zero", Packing(declarations: ["vec4 a"], values: ["a": [1, 2]]), [1, 2, 0, 0]),
        Row("a member with no value stays zero", Packing(declarations: ["float a", "float b"], values: ["b": [5]]), [0, 5, 0, 0]),
        Row(
            "a mat4 column by column",
            Packing(declarations: ["mat4 a"], values: ["a": (1...16).map(Float.init)]),
            (1...16).map(Float.init)
        ),
        Row(
            "a mat3 from nine numbers, each column padded",
            Packing(declarations: ["mat3 a"], values: ["a": (1...9).map(Float.init)]),
            [1, 2, 3, 0, 4, 5, 6, 0, 7, 8, 9, 0]
        ),
        Row(
            "a mat3 from a mat4's sixteen, its fourth row and column dropped",
            Packing(declarations: ["mat3 a"], values: ["a": (1...16).map(Float.init)]),
            [1, 2, 3, 0, 5, 6, 7, 0, 9, 10, 11, 0]
        ),
        Row(
            "an array of floats, one to a row",
            Packing(declarations: ["float a[3]"], values: ["a": [1, 2, 3]]),
            [1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0]
        ),
        Row(
            "an array of vec2, one to a row",
            Packing(declarations: ["vec2 a[2]"], values: ["a": [1, 2, 3, 4]]),
            [1, 2, 0, 0, 3, 4, 0, 0]
        ),
        Row(
            "an array of mat4, one after the other",
            Packing(declarations: ["mat4 a[2]"], values: ["a": (1...32).map(Float.init)]),
            (1...32).map(Float.init)
        ),
    ]

    @Test(arguments: packings)
    func `values are packed where the layout puts them`(row: Row<Packing, [Float]>) {
        let layout = Self.layout(row.input.declarations)

        let bytes = layout.pack { row.input.values[$0.name] }

        #expect(bytes.count == layout.size)
        #expect(Self.words(bytes) == row.expected)
    }

    @Test func `an integer is packed as an integer, a float as a float`() {
        let layout = UniformLayout.std140([
            .init(type: "int", name: "count", count: nil), .init(type: "float", name: "scale", count: nil),
            .init(type: "ivec2", name: "grid", count: nil), .init(type: "bool", name: "on", count: nil),
        ])

        let bytes = layout.pack { ["count": [3], "scale": [3], "grid": [4, 5], "on": [1]][$0.name] }

        #expect(Self.words(bytes, integers: [0, 2, 3, 4]) == [3, 3, 4, 5, 1, 0, 0, 0])
        #expect(Self.words(bytes)[1] == 3, "the float's bits are a float's")
        #expect(Self.words(bytes)[0] != 3, "the int's bits are not")
    }
}
