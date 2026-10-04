import Foundation

// Written from scratch for Livepaper, clean-room: Wallpaper Engine's own textures were never looked at,
// copied or traced. Each picture is drawn to what the samples' particle materials evidently want of it,
// read off their JSON: the size a particle is drawn at, its colour, how it blends, whether it animates.
// The `util/*` pictures follow the spike's stand-ins, which were ours too.

/// Our own stand-ins for the textures Wallpaper Engine ships itself and items
/// only name: its particle textures (`particle/halo`,
/// `particle/fog/fog1`, …) and a few `util/*` ones. Items cannot carry them and
/// we cannot ship Wallpaper Engine's, so each is drawn here, in code, to read as
/// what the samples use it for.
///
/// A picture is white or neutral with its look in its alpha: a particle's colour
/// tints it, and an additive material adds alpha × colour, so a glow's alpha is
/// its brightness. Every call draws the same picture (seeded, no `random()`).
public enum ParticleTextures {
    public struct Picture: Sendable, Equatable {
        public let width: Int
        public let height: Int
        /// RGBA8, straight (not premultiplied) alpha, rows from the top.
        public let pixels: [UInt8]
        /// A sheet of frames in a grid, left to right then top to bottom; 1 and 1 for a single picture.
        public let columns: Int
        public let rows: Int
        public let frameCount: Int
        /// Clamp at the edges (sprites) or repeat (noise).
        public let clamps: Bool

        /// Where frame `index` is, as fractions of the picture: its left, top, width and height.
        public func frameRect(_ index: Int) -> SIMD4<Float> {
            let index = min(max(index, 0), frameCount - 1)
            let (column, row) = (Float(index % columns), Float(index / columns))
            return SIMD4(column / Float(columns), row / Float(rows), 1 / Float(columns), 1 / Float(rows))
        }
    }

    /// Whether `name` is one we draw a stand-in for (a `particle/…` or `util/…` name).
    public static func draws(_ name: String) -> Bool { drawing(for: name) != nil }

    /// The stand-in for `name`, as a material names it, or nil when it is not one of Wallpaper Engine's own.
    public static func picture(for name: String) -> Picture? { drawing(for: name)?() }

    // MARK: Names

    typealias Drawing = @Sendable () -> Picture

    /// The names the samples' materials use. An unknown `util/` name has none: what it holds cannot be guessed.
    static let named: [String: Drawing] = [
        "util/white": { solid(255, 255, 255) },
        "util/black": { solid(0, 0, 0) },
        // A flow map with no flow: waterflow reads (rg * 2 - 1) as a direction.
        "util/noflow": { solid(128, 128, 0) },
        "util/noise": { whiteNoise() },
        "util/clouds_256": { clouds() },
        "particle/halo": { glow(core: 0.55) },
        "particle/halo_2": { glow(core: 0.25) },
        "particle/chromaticdot": { dot() },
        "particle/fog/fog1": { fog(seed: 0xF061) },
        "particle/fog/fog3": { fog(seed: 0xF063) },
        "particle/smoke/smoke2": { smoke() },
        "particle/debris/debris1": { flakes() },
        "particle/light/light_shafts_0": { shafts(Beam.broad) },
        "particle/light/light_shafts_6": { shafts(Beam.several) },
        "particle/beam/beam_1": { streak() },
        "particle/drop": { drop() },
        "particle/misc/wave": { rings() },
        "particle/normal_splash": { splashNormal() },
    ]

    /// Any other `particle/` name is drawn as the named picture of the first of these whose words it has, and as
    /// a soft dot when it has none.
    static let lookalikes: [(words: [String], name: String)] = [
        (["normal"], "particle/normal_splash"),
        (["debris", "leaf", "leaves", "petal", "ash", "flake"], "particle/debris/debris1"),
        (["wave", "ring", "ripple"], "particle/misc/wave"),
        (["shaft", "ray"], "particle/light/light_shafts_0"),
        (["beam", "streak", "trail"], "particle/beam/beam_1"),
        (["drop", "rain"], "particle/drop"),
        (["smoke"], "particle/smoke/smoke2"),
        (["fog", "cloud", "mist"], "particle/fog/fog1"),
        (["glow", "halo", "dot", "spark"], "particle/halo"),
    ]

    /// Short words that must start a word of the name, so that "gray" is no ray, "grain" no rain, "splash" no ash.
    static let wordStarts: Set = ["ash", "dot", "drop", "mist", "rain", "ray", "ring", "wave"]

    static func drawing(for name: String) -> Drawing? {
        var key = name.lowercased().replacingOccurrences(of: "\\", with: "/")
        if key.hasPrefix("materials/") { key.removeFirst("materials/".count) }
        if key.hasSuffix(".tex") { key.removeLast(".tex".count) }
        if let drawing = named[key] { return drawing }
        guard key.hasPrefix("particle/") else { return nil }
        let words = key.dropFirst("particle/".count).split { !$0.isLetter }
        let alike = lookalikes.first { entry in
            entry.words.contains { word in
                words.contains { wordStarts.contains(word) ? $0.hasPrefix(word) : $0.contains(word) }
            }
        }
        return alike.flatMap { named[$0.name] } ?? { softDot() }
    }
}

// MARK: Soft round things

extension ParticleTextures {
    /// `particle/halo` and `halo_2`: embers and the glow round them (additive, orange, 20 to 1000 units
    /// across) and dust motes (additive, pale yellow, 5 to 10). A soft round glow whose alpha is its
    /// brightness: a hot core, `core` of the whole, in a wide falloff gone well before the edge. `halo_2`
    /// is the softer of the two.
    static func glow(core: Float) -> Picture {
        draw(128, 128) { spot in
            let squared = spot.radius * spot.radius
            let alpha = core * exp(-squared / 0.012) + (1 - core) * exp(-squared / 0.12)
            return (1, alpha * smoothstep(1, 0.5, spot.radius))
        }
    }

    /// `particle/chromaticdot`: snow in A Lonely Winter (additive, white, 2 to 30 units, drifting) and tiny
    /// rain-splash drops (additive). A small round dot, solid in the middle with a soft edge; neutral, with no
    /// coloured fringe, so white snow stays white.
    static func dot() -> Picture {
        draw(64, 64) { spot in (1, pow(smoothstep(0.92, 0.28, spot.radius), 1.4)) }
    }

    /// Any other `particle/` texture whose name says nothing we know: a plain soft dot.
    static func softDot() -> Picture {
        draw(64, 64) { spot in
            let inside = max(0, 1 - spot.radius * spot.radius)
            return (1, inside * inside)
        }
    }

    /// `particle/fog/fog1` and `fog3`: fog banks (additive, white, alpha 0.15 to 0.3, 1000 to 2200 units,
    /// turned and slowly drifting), several overlapping. A large, very soft cloudy puff: low-frequency billows
    /// inside an outline that noise bends out of round, fading to nothing well inside the picture's edge.
    static func fog(seed: UInt64) -> Picture {
        let size = 256
        let bend = stretched(noise(size, cells: 2, octaves: 2, seed: seed))
        let billows = stretched(noise(size, cells: 3, octaves: 3, seed: seed &+ 1))
        return draw(size, size) { spot in
            let outline = smoothstep(0.95, 0.3, spot.radius + 0.7 * (bend[spot.index] - 0.5))
            let cloud = 0.4 + 0.6 * smoothstep(0.1, 0.9, billows[spot.index])
            return (1, outline * cloud * smoothstep(1, 0.75, spot.radius))
        }
    }

    /// One round lobe of a smoke puff: where it is, -1 to 1, and how far it reaches.
    struct Lobe {
        let x: Float
        let y: Float
        let reach: Float
    }

    /// `particle/smoke/smoke2`: smoke (translucent, grey, 500 to 700 units, growing). A soft billowy puff with
    /// more body than fog: round billows clustered round the middle, each lit on its top left and shaded below
    /// so that they show even in flat grey, thinned unevenly by noise.
    static func smoke() -> Picture {
        let size = 256
        var random = Seeded(0x5_40CE)
        let lobes = (0..<14).map { index in
            let angle = Float(index) * 2.4 + random.range(-0.3, 0.3), out = index < 3 ? random.range(0, 0.15) : random.range(0.2, 0.42)
            return Lobe(x: cos(angle) * out, y: sin(angle) * out, reach: index < 3 ? random.range(0.24, 0.3) : random.range(0.12, 0.2))
        }
        let wisps = stretched(noise(size, cells: 4, octaves: 3, seed: 0x5_40CF))
        return lobes.withUnsafeBufferPointer { lobes in
            draw(size, size) { spot in
                // Each billow's own light, weighed by how much of the puff there is that billow's.
                var (sum, lit): (Float, Float) = (0, 0)
                each(lobes.count) { number in
                    let lobe = lobes[number], (dx, dy) = ((spot.x - lobe.x) / lobe.reach, (spot.y - lobe.y) / lobe.reach)
                    let weight = exp(-(dx * dx + dy * dy))
                    sum += weight
                    lit += weight * (0.74 + 0.26 * min(max(-(dx * 0.6 + dy * 0.8), -1), 1))
                }
                let body = (1 - exp(-1.5 * sum)) * smoothstep(1, 0.8, spot.radius)
                return (lit / max(sum, 1e-6), body * (0.6 + 0.55 * wisps[spot.index]))
            }
        }
    }
}

// MARK: Beams, streaks and rings

extension ParticleTextures {
    /// One beam of a light shaft: where it is across the picture's top and how wide, -1 to 1, and how bright.
    struct Beam {
        static let broad = [Beam(offset: 0, width: 0.3, strength: 1)]
        static let several = [
            Beam(offset: -0.42, width: 0.07, strength: 0.6), Beam(offset: -0.12, width: 0.13, strength: 1),
            Beam(offset: 0.2, width: 0.06, strength: 0.75), Beam(offset: 0.46, width: 0.1, strength: 0.5),
        ]

        let offset: Float
        let width: Float
        let strength: Float
    }

    /// `particle/light/light_shafts_0` and `_6`: light shafts (additive, warm, 350 to 1000 units, slightly
    /// turned, long-lived). Light falling down the picture: soft at the sides, fanning out a little as it
    /// falls, streaked along its length and fading out toward the bottom. `_0` is one broad beam, `_6` several.
    static func shafts(_ beams: [Beam]) -> Picture {
        draw(256, 256) { spot in
            let fall = (spot.y + 1) / 2, across = spot.x / (1 + 0.6 * fall)
            var light: Float = 0
            each(beams.count) { index in
                let off = (across - beams[index].offset) / beams[index].width
                light += beams[index].strength * exp(-off * off)
            }
            let streaks = 0.72 + 0.28 * wobble(across * 9)
            let length = smoothstep(0, 0.16, fall) * (1 - fall * fall)
            return (1, min(1, light) * streaks * length * smoothstep(1, 0.8, abs(spot.x)))
        }
    }

    /// `particle/beam/beam_1`: a "magic" rope trail (additive, cyan). A thin soft streak down the picture, the
    /// way a trail is stretched: a bright thread in a soft glow, fading only near its ends.
    static func streak() -> Picture {
        draw(32, 128) { spot in
            let squared = spot.x * spot.x
            let across = 0.35 * exp(-squared / 0.1) + 0.65 * exp(-squared / 0.012)
            return (1, across * smoothstep(1, 0.75, abs(spot.y)))
        }
    }

    /// `particle/drop`: rain (additive, alpha up to 0.3, a sprite trail stretched along its velocity). A thin
    /// soft streak down the picture, brightest in the middle of its length, fading to nothing at both ends.
    static func drop() -> Picture {
        draw(32, 128) { spot in
            (1, exp(-spot.x * spot.x / 0.09) * pow(max(0, 1 - spot.y * spot.y), 1.5))
        }
    }

    /// `particle/misc/wave`: rain splashes on the ground (additive, `animationmode` sequence, three plays over
    /// a particle's life). A sheet of 16 frames, 4 × 4 of 64 pixels: a thin ring spreading out and fading, a
    /// fainter one following it.
    static func rings() -> Picture {
        let count = 16
        return draw(64, 64, sheet: Sheet(columns: 4, rows: 4, count: count)) { spot in
            let time = (Float(spot.frame) + 0.5) / Float(count)
            let reach = 0.12 + 0.68 * (1 - (1 - time) * (1 - time)), thickness = 0.045 + 0.04 * time
            let ring = (spot.radius - reach) / thickness, echo = (spot.radius - reach * 0.6) / (thickness * 1.3)
            let alpha = exp(-ring * ring) + 0.5 * smoothstep(0.15, 0.45, time) * exp(-echo * echo)
            return (1, alpha * smoothstep(1.05, 0.3, time) * smoothstep(1, 0.88, spot.radius))
        }
    }

    /// `particle/normal_splash`: a normal map a refracting splash bends the scene behind it with. A gentle round
    /// bump in a flat (128, 128, 255) field; its alpha a soft round mask.
    static func splashNormal() -> Picture {
        let size = 64
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        each(size * size) { index in
            let (x, y) = place(index, size)
            // A bump 0.2 × (1 - r²)² high, and its slope.
            let inside = max(0, 1 - x * x - y * y)
            let (slopeX, slopeY) = (-0.8 * x * inside, -0.8 * y * inside)
            let length = (slopeX * slopeX + slopeY * slopeY + 1).squareRoot()
            pixels[index * 4] = byte(0.5 - 0.5 * slopeX / length)
            pixels[index * 4 + 1] = byte(0.5 - 0.5 * slopeY / length)
            pixels[index * 4 + 2] = byte(0.5 + 0.5 / length)
            pixels[index * 4 + 3] = byte(smoothstep(1, 0.35, (x * x + y * y).squareRoot()))
        }
        return Picture(width: size, height: size, pixels: pixels, columns: 1, rows: 1, frameCount: 1, clamps: true)
    }
}

// MARK: Utilities

extension ParticleTextures {
    static func solid(_ red: UInt8, _ green: UInt8, _ blue: UInt8) -> Picture {
        Picture(width: 1, height: 1, pixels: [red, green, blue, 255], columns: 1, rows: 1, frameCount: 1, clamps: true)
    }

    /// `util/noise`: film grain samples it per pixel, so its texels are independent random bytes, every
    /// channel. It repeats.
    static func whiteNoise() -> Picture {
        let size = 256
        var random = Seeded(0x2545_F491_4F6C_DD1D)
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        pixels.withUnsafeMutableBytes { bytes in
            each(bytes.count / 8) { bytes.storeBytes(of: random.next(), toByteOffset: $0 * 8, as: UInt64.self) }
        }
        return Picture(width: size, height: size, pixels: pixels, columns: 1, rows: 1, frameCount: 1, clamps: false)
    }

    /// `util/clouds_256`: value noise that repeats, each channel its own.
    static func clouds() -> Picture {
        let size = 256
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        for channel in 0..<4 {
            let field = noise(size, cells: 4, octaves: 5, seed: 0xC10D &+ UInt64(channel))
            each(field.count) { pixels[$0 * 4 + channel] = byte(field[$0]) }
        }
        return Picture(width: size, height: size, pixels: pixels, columns: 1, rows: 1, frameCount: 1, clamps: false)
    }
}
