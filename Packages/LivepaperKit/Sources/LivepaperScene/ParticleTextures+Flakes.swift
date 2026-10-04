import Foundation

// Written from scratch for Livepaper, clean-room, like the rest of `ParticleTextures`.

extension ParticleTextures {
    /// `particle/debris/debris1`: sakura petals in A Lonely Winter (translucent, white to pale pink, 20 to 50
    /// units, spinning, `randomframe`) and ash in Agamemnon (translucent, grey-brown, 30 to 35, spinning,
    /// `randomframe`). A sheet of 16 frames, 4 × 4 of 128 pixels, each its own small crisp shape: eleven
    /// cherry petals, notched at the tip, some seen tilted or curled; two curled leaves; three torn flakes.
    /// White with a little shading, their edges anti-aliased over one pixel.
    static func flakes() -> Picture {
        let (frame, shapes) = (128, Flake.sheet)
        let area = frame * frame
        // Each pixel's distance from its frame's outline and the light of the face there, frame after frame;
        // 1 and 1 (well outside, white) away from the shape.
        var surfaces = [Float](repeating: 1, count: shapes.count * area * 2)
        surfaces.withUnsafeMutableBufferPointer { buffer in
            guard let surfaces = buffer.baseAddress else { return }
            for (number, shape) in shapes.enumerated() {
                let (columns, rows) = shape.near(frame)
                let (left, right, top, bottom) = (columns.lowerBound, columns.upperBound, rows.lowerBound, rows.upperBound)
                each(area) { index in
                    let (column, row) = (index % frame, index / frame)
                    guard column >= left, column <= right, row >= top, row <= bottom else { return }
                    let (x, y) = place(index, frame)
                    (surfaces[(number * area + index) * 2], surfaces[(number * area + index) * 2 + 1]) = shape.surface(x, y)
                }
            }
        }
        // Near the outline, a pixel's alpha is its distance from it in pixels, over one pixel: the change in
        // distance to the pixels either side says how much of it one pixel is. Farther off (0.1 is several
        // pixels) it is simply in or out.
        return surfaces.withUnsafeBufferPointer { buffer in
            draw(frame, frame, sheet: Sheet(columns: 4, rows: 4, count: shapes.count)) { spot in
                guard let base = buffer.baseAddress else { return (1, 0) }
                let surface = base + spot.frame * area * 2, (column, row) = (spot.index % frame, spot.index / frame)
                let (distance, light) = (surface[spot.index * 2], surface[spot.index * 2 + 1])
                guard distance.magnitude < 0.1 else { return (light, distance < 0 ? 1 : 0) }
                func at(_ column: Int, _ row: Int) -> Float { surface[(row * frame + column) * 2] }
                let across = at(min(column + 1, frame - 1), row) - at(max(column - 1, 0), row)
                let down = at(column, min(row + 1, frame - 1)) - at(column, max(row - 1, 0))
                let perPixel = max((across * across + down * down).squareRoot() / 2, 1e-6)
                return (light, min(max(0.5 - distance / perPixel, 0), 1))
            }
        }
    }
}

/// One shape on the flake sheet, in its frame from -1 to 1: a petal or a leaf along a spine that may bend,
/// or a torn flake.
private struct Flake {
    enum Outline {
        case petal
        case leaf
        case flake
    }

    static let sheet: [Flake] = [
        Flake(.petal, width: 0.34, curl: 0, length: 0.86),
        Flake(.petal, width: 0.3, curl: 0.4, length: 0.82),
        Flake(.petal, width: 0.24, curl: -0.55, length: 0.84),
        Flake(.petal, width: 0.33, curl: 0.15, length: 0.72),
        Flake(.petal, width: 0.18, curl: 0.9, length: 0.84),
        Flake(.petal, width: 0.29, curl: -0.25, length: 0.86),
        Flake(.petal, width: 0.31, curl: 0.65, length: 0.78),
        Flake(.petal, width: 0.21, curl: -1, length: 0.8),
        Flake(.petal, width: 0.34, curl: -0.1, length: 0.66),
        Flake(.petal, width: 0.12, curl: 1.2, length: 0.82),
        Flake(.petal, width: 0.27, curl: 0.45, length: 0.74),
        Flake(.leaf, width: 0.19, curl: 0.35, length: 0.86),
        Flake(.leaf, width: 0.16, curl: -0.8, length: 0.8),
        Flake(tornFrom: 0xA5E1, length: 0.78),
        Flake(tornFrom: 0xA5E2, length: 0.62),
        Flake(tornFrom: 0xA5E3, length: 0.7),
    ]

    let outline: Outline
    /// Half its width at the widest, as a share of its length: narrower for one seen tilted.
    let width: Float
    /// How far its spine turns from base to tip, in radians; 0 is flat, and negative bends it the other way.
    let curl: Float
    /// Its length, as a share of the frame's.
    let length: Float
    /// A torn flake's corners, in order round its middle, in the frame.
    let corners: [(x: Float, y: Float)]
    /// Their angles from the middle, rising.
    let angles: [Float]

    init(_ outline: Outline, width: Float, curl: Float, length: Float) {
        self.outline = outline
        self.width = width
        self.curl = curl
        self.length = length
        corners = []
        angles = []
    }

    /// A flake of six to eight corners at uneven angles and reaches, flattened, so it reads as a torn scrap.
    init(tornFrom seed: UInt64, length: Float) {
        var random = ParticleTextures.Seeded(seed)
        let count = 6 + Int(random.next() % 3), flat = random.range(0.55, 0.75)
        outline = .flake
        width = 0
        curl = 0
        self.length = length
        corners = (0..<count).map { index in
            let angle = -Float.pi + (Float(index) + random.range(0.1, 0.9)) * 2 * .pi / Float(count), reach = random.range(0.6, 1) * length
            return (cos(angle) * reach, sin(angle) * reach * flat)
        }
        angles = corners.map { atan2($0.y, $0.x) }
    }

    /// The columns and rows of a frame `size` pixels across that the shape is in or near, so that the rest of
    /// the frame need not be worked out pixel by pixel: a first look every 8 pixels finds the points within
    /// 0.15 of it (more than 7 pixels, the farthest any pixel is from one looked at, and its neighbour), and
    /// each of those takes in the 8 pixels round it.
    func near(_ size: Int) -> (columns: ClosedRange<Int>, rows: ClosedRange<Int>) {
        var (left, right, top, bottom) = (size, -1, size, -1)
        for row in stride(from: 4, to: size, by: 8) {
            for column in stride(from: 4, to: size, by: 8) {
                let (x, y) = ParticleTextures.place(row * size + column, size)
                guard surface(x, y).distance < 0.15 else { continue }
                (left, right, top, bottom) = (min(left, column), max(right, column), min(top, row), max(bottom, row))
            }
        }
        guard right >= 0 else { return (0...size - 1, 0...size - 1) }
        return (max(left - 8, 0)...min(right + 8, size - 1), max(top - 8, 0)...min(bottom + 8, size - 1))
    }

    /// How far a point is from the outline, more or less, negative inside; and how light the face is there, 0 to 1.
    func surface(_ x: Float, _ y: Float) -> (distance: Float, light: Float) {
        guard outline != .flake else { return torn(x, y) }
        let span = length * 2
        var (along, across) = (0.5 - y / span, x / span)
        if abs(curl) > 0.01 {
            // The spine is an arc bulging left (right for a negative curl), its chord across the frame's middle.
            let bend = abs(curl), radius = span / bend
            let (dx, dy) = ((curl > 0 ? x : -x) - radius * (1 + cos(bend / 2)) / 2, y)
            along = (bend / 2 - atan2(dy, -dx)) / bend
            across = ((dx * dx + dy * dy).squareRoot() - radius) / span
        }
        var distance = abs(across) - halfWidth(along)
        // A small notch in the middle of a petal's round tip.
        if outline == .petal { distance = max(distance, (along - 0.93) * 0.4 - abs(across)) }
        guard distance < 0.05 else { return (distance, 1) }
        // A petal pales from its base to its tip and has a faint crease down its middle, a leaf a darker midrib;
        // a bent one is shaded on its far side.
        let leaf = outline == .leaf
        let crease = exp(-across * across / (leaf ? 0.0002 : 0.001)) * (1 - 0.6 * along) * (leaf ? 0.22 : 0.07)
        let face = 0.82 + 0.18 * ParticleTextures.smoothstep(0, 0.6, along) - crease
        return (distance, face * (abs(curl) > 0.01 ? 0.95 - 0.1 * across / max(width, 0.01) : 1))
    }

    /// Half the width at `along`, in lengths; below zero past either end, so the outline closes there. A petal
    /// is widest a little past halfway, round at its tip and narrowing to a slender base; a leaf is pointed at
    /// both ends.
    func halfWidth(_ along: Float) -> Float {
        guard along > 0, along < 1 else { return along <= 0 ? along : 1 - along }
        if outline == .leaf { return width * pow(sin(along * .pi), 0.8) }
        guard along > 0.6 else { return width * pow(sin(along / 0.6 * .pi / 2), 1.5) }
        let over = (along - 0.6) / 0.4
        return width * (1 - over * over).squareRoot()
    }

    /// A torn flake: straight edges between its corners; lighter on one side, with a faint fold across it.
    func torn(_ x: Float, _ y: Float) -> (distance: Float, light: Float) {
        let angle = atan2(y, x)
        // The corner before the point, going round: the last whose angle is no more than the point's.
        var first = corners.count - 1
        ParticleTextures.each(corners.count) { if angles[$0] <= angle { first = $0 } }
        let second = (first + 1) % corners.count
        let (start, edge) = (corners[first], (x: corners[second].x - corners[first].x, y: corners[second].y - corners[first].y))
        // How far from the middle the edge is in the point's direction.
        let (towardX, towardY) = (cos(angle), sin(angle))
        let reach = (start.x * edge.y - start.y * edge.x) / (towardX * edge.y - towardY * edge.x)
        let fold = x * 0.8 + y * 0.6
        let light = 0.84 + 0.12 * (y - x) / length - 0.1 * exp(-fold * fold / 0.0015)
        return ((x * x + y * y).squareRoot() - reach, light)
    }
}
