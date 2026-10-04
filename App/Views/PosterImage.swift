import DesignSystem
import ImageIO
import SwiftUI

/// A wallpaper's poster from its file (HEIC), decoded off the main actor at the
/// size it is shown and no larger, and kept for the next time it is shown.
///
/// Drawn filling its frame, or handed as an `Image` to `content`, which is how
/// the design system's components take a poster. Nil until it has loaded.
struct PosterImage<Content: View>: View {
    let url: URL?
    /// Changes when the file is written again (`WallpaperArt.posterChanged`), and it is read again.
    let revision: Int
    private let content: (Image?) -> Content

    @Environment(\.displayScale) private var displayScale
    @State private var size = CGSize.zero
    @State private var loaded: PosterCache.Entry?

    init(url: URL?, revision: Int = 0, @ViewBuilder content: @escaping (Image?) -> Content) {
        self.url = url
        self.revision = revision
        self.content = content
    }

    var body: some View {
        let request = url.map { PosterCache.Request(url: $0, size: size, scale: displayScale, revision: revision) }
        // One decoded before shows at once; a smaller one stays up while a larger one decodes.
        let entry = request.flatMap(PosterCache.shared.cached) ?? loaded.flatMap { $0.url == url ? $0 : nil }
        content(entry.map { Image(decorative: $0.image, scale: displayScale) })
            .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
            .task(id: request) {
                guard let request, request.isDrawable else { return }
                loaded = await PosterCache.shared.load(request)
            }
    }
}

extension PosterImage where Content == PosterFill {
    /// The poster filling the frame it is given, cropped to it.
    init(url: URL?) {
        self.init(url: url) { PosterFill(image: $0) }
    }
}

/// The poster filling its frame, or nothing while it loads.
struct PosterFill: View {
    let image: Image?

    var body: some View {
        Color.clear
            .overlay {
                image?
                    .resizable()
                    .scaledToFill()
            }
            .clipped()
            .accessibilityHidden(true)
    }
}

/// Decoded posters, shared across the app. Each is decoded to cover the size it
/// is shown at, in steps, so a window being resized does not decode it again at
/// every point.
nonisolated final class PosterCache: @unchecked Sendable {
    static let shared = PosterCache()

    /// A poster to show at `size` points on a display of `scale`, as its file
    /// was after it had been written `revision` times since launch.
    struct Request: Hashable, Sendable {
        var url: URL
        var size: CGSize
        var scale: CGFloat
        var revision = 0

        /// The longest side the decoded image needs, rounded up to the next step.
        var pixels: Int {
            let longest = max(size.width, size.height) * scale
            return Int((longest / PosterCache.step).rounded(.up)) * Int(PosterCache.step)
        }

        var isDrawable: Bool { size.width > 0 && size.height > 0 }
    }

    struct Entry: Sendable {
        let url: URL
        let image: CGImage
        /// The longest side it was decoded to cover.
        let pixels: Int
        /// The file's revision it was decoded from (`Request.revision`).
        let revision: Int
    }

    private static let step: CGFloat = 128

    // NSCache is thread-safe, and lets go of posters under memory pressure.
    private let entries = NSCache<NSString, Box>()

    private final class Box {
        let entry: Entry
        init(_ entry: Entry) { self.entry = entry }
    }

    /// The poster, if it has been decoded at this size or larger, from this revision of its file or a later one.
    func cached(_ request: Request) -> Entry? {
        entries.object(forKey: request.url.path as NSString).flatMap {
            $0.entry.pixels >= request.pixels && $0.entry.revision >= request.revision ? $0.entry : nil
        }
    }

    /// Decodes the poster to cover `request.size`, off the main actor. Nil when the
    /// file cannot be read, such as a poster that has left the library.
    func load(_ request: Request) async -> Entry? {
        if let entry = cached(request) { return entry }
        guard let entry = await Self.decode(request) else { return nil }
        // One decoded from a later revision meanwhile is kept.
        let kept = entries.object(forKey: request.url.path as NSString)?.entry
        if kept.map({ $0.revision <= entry.revision }) ?? true {
            entries.setObject(Box(entry), forKey: request.url.path as NSString)
        }
        return entry
    }

    @concurrent
    private static func decode(_ request: Request) async -> Entry? {
        guard let source = CGImageSourceCreateWithURL(request.url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0 else { return nil }
        // Filling the frame, the picture's longest side overshoots the frame's; it
        // is never decoded larger than it is.
        let cover = max(request.size.width / CGFloat(width), request.size.height / CGFloat(height))
        let longest = min(max(width, height), Int((CGFloat(max(width, height)) * cover * request.scale).rounded(.up)))
        let pixels = max(longest, request.pixels)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return Entry(url: request.url, image: image, pixels: pixels, revision: request.revision)
    }
}

#Preview("A poster file") {
    // Draws a poster, writes it as HEIC and reads it back, as a library poster is read.
    let file = URL.temporaryDirectory.appending(path: "poster-preview.heic")
    if let image = DrawnPoster.cgImage(seed: 11),
       let destination = CGImageDestinationCreateWithURL(file as CFURL, "public.heic" as CFString, 1, nil) {
        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }
    return VStack(spacing: Spacing.large) {
        PosterImage(url: file)
            .frame(width: 320, height: 200)
            .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        PosterImage(url: file) { image in
            WallpaperTile(
                id: 1,
                poster: image ?? Image(systemName: "photo"),
                title: "Harbour at Dusk",
                action: {},
                livePreview: { EmptyView() }
            )
            .frame(width: 200)
        }
    }
    .padding(Spacing.large)
}
