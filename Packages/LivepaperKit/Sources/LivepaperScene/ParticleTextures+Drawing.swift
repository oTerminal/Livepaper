import Foundation

// Written from scratch for Livepaper, clean-room, like the rest of `ParticleTextures`: the tools its
// pictures are drawn with.

extension ParticleTextures {
    /// How a picture is cut into frames.
    struct Sheet {
        static let single = Sheet(columns: 1, rows: 1, count: 1)

        let columns: Int
        let rows: Int
        let count: Int
    }

    /// A pixel being drawn: its frame, where it is in the frame from -1 to 1 (left to right, top to bottom),
    /// and its index in the frame, for fields worked out beforehand.
    struct Spot {
        let frame: Int
        let x: Float
        let y: Float
        let index: Int

        var radius: Float { (x * x + y * y).squareRoot() }
    }

    /// A white picture of frames `width` × `height` from each pixel's lightness and alpha, 0 to 1.
    static func draw(_ width: Int, _ height: Int, sheet: Sheet = .single, pixel: (Spot) -> (light: Float, alpha: Float)) -> Picture {
        let (sheetWidth, sheetHeight) = (width * sheet.columns, height * sheet.rows)
        var pixels = [UInt8](repeating: 0, count: sheetWidth * sheetHeight * 4)
        // Written through a pointer: an array's own subscript costs more than the pixel in a debug build.
        pixels.withUnsafeMutableBufferPointer { buffer in
            guard let pixels = buffer.baseAddress else { return }
            for frame in 0..<sheet.count {
                let (left, top) = (frame % sheet.columns * width, frame / sheet.columns * height)
                each(width * height) { index in
                    let (column, row) = (index % width, index / width)
                    let x = (Float(column) + 0.5) / Float(width) * 2 - 1, y = (Float(row) + 0.5) / Float(height) * 2 - 1
                    let tone = pixel(Spot(frame: frame, x: x, y: y, index: index))
                    let start = pixels + ((top + row) * sheetWidth + left + column) * 4, light = byte(tone.light)
                    start[0] = light
                    start[1] = light
                    start[2] = light
                    start[3] = byte(tone.alpha)
                }
            }
        }
        return Picture(
            width: sheetWidth, height: sheetHeight, pixels: pixels,
            columns: sheet.columns, rows: sheet.rows, frameCount: sheet.count, clamps: true
        )
    }

    /// Value noise that repeats every `size` pixels, 0 to 1: random values on a lattice of `cells` × `cells`,
    /// smoothly interpolated, and `octaves - 1` finer lattices, each twice as fine at half the weight.
    static func noise(_ size: Int, cells: Int, octaves: Int, seed: UInt64) -> [Float] {
        var random = Seeded(seed)
        var sum = [Float](repeating: 0, count: size * size)
        var (cells, weight, total) = (cells, Float(1), Float(0))
        for _ in 0..<octaves {
            let lattice = field(cells * cells) { _ in random.unit() }
            // For each column (and row), the lattice points either side and how far between them, eased.
            let positions = field(size) { (Float($0) + 0.5) / Float(size) * Float(cells) }
            let lower = positions.map { Int($0) % cells }, upper = positions.map { (Int($0) + 1) % cells }
            let ease = positions.map { position in
                let fraction = position - position.rounded(.down)
                return fraction * fraction * (3 - 2 * fraction)
            }
            // Along each row of the lattice first, then between two of those: one blend a pixel.
            let rows = field(cells * size) { index in
                let (row, column) = (index / size * cells, index % size)
                return lattice[row + lower[column]] + (lattice[row + upper[column]] - lattice[row + lower[column]]) * ease[column]
            }
            rows.withUnsafeBufferPointer { rows in
                sum.withUnsafeMutableBufferPointer { sum in
                    guard let rows = rows.baseAddress, let sum = sum.baseAddress else { return }
                    for row in 0..<size {
                        let (above, below, down, into) = (rows + lower[row] * size, rows + upper[row] * size, ease[row], sum + row * size)
                        each(size) { into[$0] += (above[$0] + (below[$0] - above[$0]) * down) * weight }
                    }
                }
            }
            total += weight
            weight *= 0.5
            cells *= 2
        }
        each(sum.count) { sum[$0] /= total }
        return sum
    }

    /// `field` spread to run from 0 to 1.
    static func stretched(_ field: [Float]) -> [Float] {
        var (low, high) = (Float.infinity, -Float.infinity)
        each(field.count) { index in
            low = min(low, field[index])
            high = max(high, field[index])
        }
        return self.field(field.count) { (field[$0] - low) / max(high - low, 1e-6) }
    }

    /// Where pixel `index` of a square picture `size` across is, from -1 to 1.
    static func place(_ index: Int, _ size: Int) -> (x: Float, y: Float) {
        ((Float(index % size) + 0.5) / Float(size) * 2 - 1, (Float(index / size) + 0.5) / Float(size) * 2 - 1)
    }

    /// `count` numbers, `value` of each index. This and `each` are `while` loops, as is every loop here that
    /// runs once a pixel: in a debug build a `for` over a range costs some 80 ns a turn, most of a picture's time.
    static func field(_ count: Int, _ value: (Int) -> Float) -> [Float] {
        var field = [Float](repeating: 0, count: count)
        each(count) { field[$0] = value($0) }
        return field
    }

    static func each(_ count: Int, _ body: (Int) -> Void) {
        var index = 0
        while index < count {
            body(index)
            index += 1
        }
    }

    static func smoothstep(_ edge0: Float, _ edge1: Float, _ value: Float) -> Float {
        let fraction = min(max((value - edge0) / (edge1 - edge0), 0), 1)
        return fraction * fraction * (3 - 2 * fraction)
    }

    /// A fixed wobble between about 0 and 1 with no clear period, for streaks.
    static func wobble(_ value: Float) -> Float {
        0.5 + 0.22 * sin(value * 1.7 + 0.4) + 0.17 * sin(value * 3.1 + 1.9) + 0.11 * sin(value * 5.3 + 4.1)
    }

    static func byte(_ value: Float) -> UInt8 { value <= 0 ? 0 : value >= 1 ? 255 : UInt8(value * 255 + 0.5) }

    /// SplitMix64: numbers that look random but are the same for the same seed, so every picture is too.
    struct Seeded {
        private var state: UInt64

        init(_ seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return mixed ^ (mixed >> 31)
        }

        /// 0 up to 1.
        mutating func unit() -> Float { Float(next() >> 40) / Float(1 << 24) }

        mutating func range(_ low: Float, _ high: Float) -> Float { low + (high - low) * unit() }
    }
}
