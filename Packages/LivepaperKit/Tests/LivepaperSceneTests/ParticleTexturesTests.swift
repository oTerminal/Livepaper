import Foundation
import Testing
import LivepaperScene

struct ParticleTexturesTests {
    typealias Picture = ParticleTextures.Picture

    /// Every Wallpaper Engine texture the samples' materials name and no item carries.
    static let named = [
        "util/white", "util/black", "util/noise", "util/noflow", "util/clouds_256",
        "particle/halo", "particle/halo_2", "particle/chromaticdot", "particle/fog/fog1", "particle/fog/fog3",
        "particle/smoke/smoke2", "particle/debris/debris1", "particle/light/light_shafts_0", "particle/light/light_shafts_6",
        "particle/beam/beam_1", "particle/drop", "particle/misc/wave", "particle/normal_splash",
    ]

    static func picture(_ name: String) throws -> Picture { try #require(ParticleTextures.picture(for: name)) }

    // MARK: Names

    @Test(arguments: named)
    func `each name the samples use has a picture, as big as it says`(name: String) throws {
        let picture = try Self.picture(name)

        #expect(ParticleTextures.draws(name))
        #expect(picture.pixels.count == picture.width * picture.height * 4)
        #expect((1...picture.columns * picture.rows).contains(picture.frameCount))
        #expect(picture.width.isMultiple(of: picture.columns) && picture.height.isMultiple(of: picture.rows))
    }

    @Test(arguments: [
        "materials/sky", "effects/waterripple/waterripplenormal", "util/somethingnew", "particles/halo", "halo", "",
    ])
    func `a name that is not one of Wallpaper Engine's own textures has none`(name: String) {
        #expect(!ParticleTextures.draws(name))
        #expect(ParticleTextures.picture(for: name) == nil)
    }

    static let lookalikes: [Row<String, String>] = [
        Row("case, backslashes, a materials folder and a .tex ending are the same name", #"materials\Particle\Halo.tex"#, "particle/halo"),
        Row("sparks glow", "particle/sparks/spark_big", "particle/halo"),
        Row("a glow in a longer word glows", "particle/misc/softglow", "particle/halo"),
        Row("mist is fog", "particle/mist01", "particle/fog/fog1"),
        Row("clouds are fog", "particle/sky/clouds_2", "particle/fog/fog1"),
        Row("smoke is smoke", "particle/smoke/smoke5", "particle/smoke/smoke2"),
        Row("grey smoke is no ray of light", "particle/smoke_gray", "particle/smoke/smoke2"),
        Row("leaves are flakes", "particle/nature/leaves_3", "particle/debris/debris1"),
        Row("petals are flakes", "particle/sakura_petal", "particle/debris/debris1"),
        Row("ash is flakes", "particle/ash", "particle/debris/debris1"),
        Row("a snowflake is a flake, not a dot", "particle/snowflake", "particle/debris/debris1"),
        Row("rays are a shaft of light", "particle/light/god_rays", "particle/light/light_shafts_0"),
        Row("a streak is a streak", "particle/streak_2", "particle/beam/beam_1"),
        Row("a trail is a streak", "particle/magic/trail", "particle/beam/beam_1"),
        Row("rain is a drop", "particle/rain/rain1", "particle/drop"),
        Row("a ripple is rings", "particle/water/ripple", "particle/misc/wave"),
        Row("a splash that glows is no ash", "particle/splash_glow", "particle/halo"),
        Row("a normal map stays a normal map", "particle/normal_drop", "particle/normal_splash"),
    ]

    @Test(arguments: lookalikes)
    func `another particle texture is drawn as the one its name is like`(row: Row<String, String>) throws {
        #expect(ParticleTextures.draws(row.input))
        #expect(try Self.picture(row.input) == Self.picture(row.expected))
    }

    @Test func `a particle texture whose name says nothing known is a soft dot`() throws {
        let dot = try Self.picture("particle/misc/thing7")

        #expect([dot.width, dot.height, dot.frameCount] == [64, 64, 1] as [Int])
        // Round: as solid a quarter of the way in from each side as from the others.
        let quarter: Set<UInt8> = [dot.alpha(16, 32), dot.alpha(47, 32), dot.alpha(32, 16), dot.alpha(32, 47)]
        #expect(quarter.count == 1)
        #expect(quarter.allSatisfy { $0 > 64 })
    }

    // MARK: Pictures

    static let soft = [
        "particle/halo", "particle/halo_2", "particle/chromaticdot", "particle/fog/fog1", "particle/fog/fog3",
        "particle/smoke/smoke2", "particle/light/light_shafts_0", "particle/light/light_shafts_6", "particle/beam/beam_1",
        "particle/drop", "particle/misc/thing7",
    ]

    @Test(arguments: soft)
    func `a soft picture fades to nothing at its edges and is solid in its middle`(name: String) throws {
        let picture = try Self.picture(name)
        let middle = (picture.height / 3..<picture.height * 2 / 3).flatMap { row in
            (picture.width / 3..<picture.width * 2 / 3).map { picture.alpha($0, row) }
        }

        #expect(picture.clamps)
        #expect(picture.rim(0).allSatisfy { $0 <= 2 })
        #expect([picture.alpha(0, 0), picture.alpha(picture.width - 1, picture.height - 1)] == [0, 0])
        #expect(middle.max() ?? 0 >= 128)
    }

    @Test(arguments: named.filter { !$0.hasPrefix("util/") && $0 != "particle/normal_splash" })
    func `a picture a particle's colour tints is white or grey`(name: String) throws {
        let pixels = try Self.picture(name).pixels
        let grey = stride(from: 0, to: pixels.count, by: 4).allSatisfy { (start: Int) -> Bool in
            let red: UInt8 = pixels[start]
            return red == pixels[start + 1] && red == pixels[start + 2]
        }

        #expect(grey)
    }

    static let sheets: [Row<String, [Int]>] = [
        Row("petals, leaves and flakes, one picked at random for each particle", "particle/debris/debris1", [4, 4, 16]),
        Row("a ring spreading, shown frame after frame over a particle's life", "particle/misc/wave", [4, 4, 16]),
    ]

    @Test(arguments: sheets)
    func `a sheet has its frames in a grid, each its own and clear of the next`(row: Row<String, [Int]>) throws {
        let sheet = try Self.picture(row.input)
        let frames = (0..<sheet.frameCount).map(sheet.frame)

        #expect([sheet.columns, sheet.rows, sheet.frameCount] == row.expected)
        #expect(Set(frames).count == frames.count)
        for index in frames.indices {
            #expect(sheet.rim(index).allSatisfy { $0 == 0 }, "frame \(index) touches its edge")
            #expect(stride(from: 3, to: frames[index].count, by: 4).contains { frames[index][$0] > 0 }, "frame \(index) is empty")
        }
    }

    @Test func `the petals and flakes are crisp: solid inside, clear outside, a pixel of edge between`() throws {
        let sheet = try Self.picture("particle/debris/debris1")

        for index in 0..<sheet.frameCount {
            let frame = sheet.frame(index)
            let alphas = stride(from: 3, to: frame.count, by: 4).map { frame[$0] }
            let (solid, edge) = (alphas.count { $0 == 255 }, alphas.count { $0 > 0 && $0 < 255 })
            #expect(solid > 1000 && edge < solid / 3, "frame \(index): \(solid) solid, \(edge) edge")
        }
    }

    @Test func `a splash's ring spreads out frame by frame`() throws {
        let sheet = try Self.picture("particle/misc/wave")
        let side = sheet.width / sheet.columns

        // How far from the frame's middle its alpha lies, on average.
        let reaches = (0..<sheet.frameCount).map { index in
            let pixels = sheet.frame(index)
            var (weighted, total) = (0.0, 0.0)
            for pixel in 0..<side * side {
                let (dx, dy) = (Double(pixel % side) + 0.5 - Double(side) / 2, Double(pixel / side) + 0.5 - Double(side) / 2)
                weighted += Double(pixels[pixel * 4 + 3]) * (dx * dx + dy * dy).squareRoot()
                total += Double(pixels[pixel * 4 + 3])
            }
            return weighted / total
        }
        #expect(zip(reaches, reaches.dropFirst()).allSatisfy { $0 < $1 }, "\(reaches)")
    }

    @Test func `a frame's place in its sheet is given as fractions of the picture`() throws {
        let sheet = try Self.picture("particle/misc/wave")

        #expect(sheet.frameRect(0) == SIMD4(0, 0, 0.25, 0.25))
        #expect(sheet.frameRect(6) == SIMD4(0.5, 0.25, 0.25, 0.25))
        #expect(sheet.frameRect(15) == SIMD4(0.75, 0.75, 0.25, 0.25))
    }

    static let solids: [Row<String, [UInt8]>] = [
        Row("white", "util/white", [255, 255, 255, 255]),
        Row("black", "util/black", [0, 0, 0, 255]),
        Row("a flow map with no flow", "util/noflow", [128, 128, 0, 255]),
    ]

    @Test(arguments: solids)
    func `a flat utility texture is its one colour`(row: Row<String, [UInt8]>) throws {
        #expect(try Self.picture(row.input).pixels == row.expected)
    }

    @Test func `util/noise is independent random texels in every channel, and repeats`() throws {
        let noise = try Self.picture("util/noise")
        let pixels = noise.pixels.map(Double.init)

        #expect(!noise.clamps)
        #expect([noise.width, noise.height] == [256, 256] as [Int])
        for channel in 0..<4 {
            let values = stride(from: channel, to: pixels.count, by: 4).map { pixels[$0] }
            let mean = values.reduce(0, +) / Double(values.count)
            // Next to each other, two independent values 0 to 255 differ by 85 on average.
            let step = zip(values, values.dropFirst()).map { abs($0 - $1) }.reduce(0, +) / Double(values.count - 1)
            #expect(abs(mean - 127.5) < 3 && abs(step - 85) < 4, "channel \(channel): mean \(mean), step \(step)")
        }
    }

    @Test func `util/clouds_256 repeats with no seam`() throws {
        let clouds = try Self.picture("util/clouds_256")
        let size = clouds.width
        func value(_ column: Int, _ row: Int, _ channel: Int) -> Double { Double(clouds.pixels[(row * size + column) * 4 + channel]) }
        // The step from the last column to the first (and the last row to the first) against a step inside.
        var (inside, acrossSeam, downSeam) = (0.0, 0.0, 0.0)
        for index in 0..<size {
            for channel in 0..<4 {
                inside += abs(value(size / 2, index, channel) - value(size / 2 - 1, index, channel))
                acrossSeam += abs(value(0, index, channel) - value(size - 1, index, channel))
                downSeam += abs(value(index, 0, channel) - value(index, size - 1, channel))
            }
        }

        #expect(!clouds.clamps)
        #expect(acrossSeam < inside * 2 && downSeam < inside * 2, "inside \(inside), seams \(acrossSeam), \(downSeam)")
        #expect(Set(clouds.pixels).count > 100)
    }

    @Test func `the splash's normal map is flat at its edges and bends gently between`() throws {
        let normals = try Self.picture("particle/normal_splash")
        let size = normals.width
        func normal(_ column: Int, _ row: Int) -> [UInt8] {
            let start = (row * size + column) * 4
            return Array(normals.pixels[start..<start + 3])
        }

        let flat: [UInt8] = [128, 128, 255]
        #expect(normal(0, 0) == flat)
        #expect(normal(size - 1, size - 1) == flat)
        #expect((0..<size * size).allSatisfy { normal($0 % size, $0 / size)[2] >= 230 })
        #expect((0..<size).contains { abs(Int(normal($0, size / 2)[0]) - 128) > 20 })
    }

    @Test(arguments: named)
    func `a name draws the same picture every time`(name: String) throws {
        #expect(try Self.picture(name) == Self.picture(name))
    }
}

private extension ParticleTextures.Picture {
    func alpha(_ column: Int, _ row: Int) -> UInt8 { pixels[(row * width + column) * 4 + 3] }

    /// Frame `index`'s pixels, RGBA, rows from the top.
    func frame(_ index: Int) -> [UInt8] {
        let (side, tall) = (width / columns, height / rows)
        let (left, top) = (index % columns * side, index / columns * tall)
        return (top..<top + tall).flatMap { (row: Int) -> ArraySlice<UInt8> in
            let start: Int = (row * width + left) * 4
            return pixels[start..<start + side * 4]
        }
    }

    /// The alphas all round the edge of frame `index`.
    func rim(_ index: Int) -> [UInt8] {
        let (side, tall) = (width / columns, height / rows)
        let pixels = frame(index)
        let topAndBottom: [Int] = (0..<side).flatMap { (column: Int) -> [Int] in [column, (tall - 1) * side + column] }
        let leftAndRight: [Int] = (0..<tall).flatMap { (row: Int) -> [Int] in [row * side, row * side + side - 1] }
        return (topAndBottom + leftAndRight).map { (at: Int) -> UInt8 in pixels[at * 4 + 3] }
    }
}
