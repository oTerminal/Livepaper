import SwiftUI

/// A stand-in for a wallpaper poster, drawn rather than bundled: a mesh gradient
/// with hard-edged shapes on top, so glass has something busy to sit over.
struct SamplePicture: View {
    let seed: Int

    static let size = CGSize(width: 1600, height: 1000)

    var body: some View {
        var generator = SeededGenerator(seed: UInt64(seed))
        let hue = Double.random(in: 0...1, using: &generator)
        let colors = (0..<9).map { index in
            Color(
                hue: (hue + Double(index) * Double.random(in: 0.03...0.09, using: &generator)).truncatingRemainder(dividingBy: 1),
                saturation: Double.random(in: 0.55...0.95, using: &generator),
                brightness: Double.random(in: 0.35...0.95, using: &generator)
            )
        }
        let discs = (0..<6).map { _ in
            (
                x: Double.random(in: 0...1, using: &generator),
                y: Double.random(in: 0...1, using: &generator),
                size: Double.random(in: 0.08...0.3, using: &generator),
                white: Bool.random(using: &generator)
            )
        }
        return MeshGradient(
            width: 3,
            height: 3,
            points: [[0, 0], [0.5, 0], [1, 0], [0, 0.5], [0.4, 0.6], [1, 0.5], [0, 1], [0.5, 1], [1, 1]],
            colors: colors
        )
        .overlay {
            Canvas { context, size in
                for disc in discs {
                    let side = disc.size * size.width
                    let rect = CGRect(x: disc.x * size.width - side / 2, y: disc.y * size.height - side / 2, width: side, height: side)
                    context.fill(Path(ellipseIn: rect), with: .color(disc.white ? .white.opacity(0.85) : .black.opacity(0.7)))
                }
            }
        }
    }

    /// The picture as an `Image`, which is what components take.
    @MainActor static func image(seed: Int) -> Image {
        let renderer = ImageRenderer(content: SamplePicture(seed: seed).frame(width: size.width / 4, height: size.height / 4))
        renderer.scale = 2
        guard let image = renderer.nsImage else { return Image(systemName: "photo") }
        return Image(nsImage: image)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    // SplitMix64.
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
        return mixed ^ (mixed >> 31)
    }
}
