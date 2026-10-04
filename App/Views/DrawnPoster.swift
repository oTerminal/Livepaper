import AppKit
import DesignSystem
import LivepaperTestSupport
import SwiftUI

/// A poster drawn rather than read from a file, for the fakes run and previews:
/// a mesh gradient with hard-edged discs on top, as the Gallery's `SamplePicture`
/// draws it, so glass has something busy to sit over. The same seed draws the
/// same picture.
struct DrawnPoster: View {
    let seed: Int

    /// 16:10, the shape of a tile's poster.
    static let size = CGSize(width: 1600, height: 1000)

    var body: some View {
        var generator = SeededGenerator(seed: UInt64(bitPattern: Int64(seed)))
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
        .accessibilityHidden(true)
    }

    /// The picture as pixels, `pointSize` at 2x.
    static func cgImage(seed: Int, pointSize: CGSize = CGSize(width: size.width / 4, height: size.height / 4)) -> CGImage? {
        let renderer = ImageRenderer(content: DrawnPoster(seed: seed).frame(width: pointSize.width, height: pointSize.height))
        renderer.scale = 2
        return renderer.cgImage
    }

    /// The picture as JPEG: a Wallpaper Engine item's preview in the fakes run's sample files.
    static func jpeg(seed: Int) -> Data? {
        guard let image = cgImage(seed: seed) else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [:])
    }

    /// The picture as an `Image`, which is what the design system's components take.
    static func image(seed: Int) -> Image {
        guard let image = cgImage(seed: seed) else { return Image(systemName: "photo") }
        return Image(decorative: image, scale: 2)
    }
}

#Preview {
    HStack(spacing: Spacing.medium) {
        ForEach(1..<4) { seed in
            DrawnPoster.image(seed: seed)
                .resizable()
                .aspectRatio(16 / 10, contentMode: .fit)
                .frame(width: 200)
                .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        }
    }
    .padding(Spacing.large)
}
