import Foundation
import LivepaperCore
import Observation
import SwiftUI

/// Where the screens get a wallpaper's pictures: its poster as an `Image`, which
/// is what the design system's components take, and the files a preview plays.
///
/// Wired, they are the library's files, and a poster is decoded off the main
/// actor at the size asked for (`PosterCache`). In the fakes run posters are
/// drawn from the wallpaper's identifier and there is nothing to play, so the
/// poster stays wherever a preview would go.
@Observable
final class WallpaperArt {
    enum Source {
        case library(LibraryLocation)
        case drawn
    }

    let source: Source

    /// Counts the posters decoded, so that a view that asked before its poster
    /// was ready is drawn again when it is.
    private var decodedCount = 0
    /// How many times each poster file was written again since launch (a scene's,
    /// drawn from the scene: `ScenePoster`), so that one decoded before is decoded again.
    private var revisions: [URL: Int] = [:]
    @ObservationIgnored private var decoding: Set<PosterCache.Request> = []
    /// Pictures that could not be read, never asked for again.
    @ObservationIgnored private var unreadable: Set<URL> = []
    @ObservationIgnored private var drawn: [WallpaperID: Image] = [:]

    init(_ source: Source) {
        self.source = source
    }

    /// The wallpaper's poster, to cover `size` points. Nil until it has been
    /// decoded; the view asking is drawn again then.
    func poster(for wallpaper: Wallpaper, size: CGSize, scale: CGFloat = 2) -> Image? {
        switch source {
        case .library(let location):
            picture(at: location.url(for: wallpaper.poster), size: size, scale: scale)
        case .drawn:
            drawnPoster(for: wallpaper.id)
        }
    }

    /// Any picture file, such as a Wallpaper Engine item's preview in the import list.
    func picture(at url: URL, size: CGSize, scale: CGFloat = 2) -> Image? {
        let request = PosterCache.Request(url: url, size: size, scale: scale, revision: revisions[url] ?? 0)
        guard request.isDrawable, !unreadable.contains(url) else { return nil }
        // Read, so that a poster decoded later draws the view again.
        _ = decodedCount
        if let entry = PosterCache.shared.cached(request) {
            return Image(decorative: entry.image, scale: scale)
        }
        if decoding.insert(request).inserted {
            Task {
                if await PosterCache.shared.load(request) == nil {
                    unreadable.insert(url)
                }
                decoding.remove(request)
                decodedCount += 1
            }
        }
        // A poster written again keeps its earlier picture up until the new one is decoded.
        guard request.revision > 0 else { return nil }
        let earlier = PosterCache.Request(url: url, size: size, scale: scale)
        return PosterCache.shared.cached(earlier).map { Image(decorative: $0.image, scale: scale) }
    }

    /// The poster file, for `PosterImage`; nil in the fakes run.
    func posterURL(for wallpaper: Wallpaper) -> URL? {
        guard case .library(let location) = source else { return nil }
        return location.url(for: wallpaper.poster)
    }

    /// How many times the wallpaper's poster file was written again since launch, for `PosterImage`.
    func posterRevision(for wallpaper: Wallpaper) -> Int {
        posterURL(for: wallpaper).flatMap { revisions[$0] } ?? 0
    }

    /// The wallpaper's poster file was written again, as a scene's is once it is
    /// drawn from the scene: every view showing it reads it again, keeping the
    /// picture it has until the new one is decoded.
    func posterChanged(for wallpaper: Wallpaper) {
        guard let url = posterURL(for: wallpaper) else { return }
        revisions[url, default: 0] += 1
        unreadable.remove(url)
    }

    /// What a tile plays once it goes live: the hover preview. Nil when the
    /// import made none, and in the fakes run: the poster stays.
    func hoverPreviewURL(for wallpaper: Wallpaper) -> URL? {
        guard case .library(let location) = source, let preview = wallpaper.hoverPreview else { return nil }
        return location.url(for: preview)
    }

    /// What the inspector's preview plays: the optimised copy. A scene is drawn
    /// only on a display, so its preview plays its hover preview,
    /// or nothing, and the poster stays. Nil in the fakes run.
    func inspectorPreviewURL(for wallpaper: Wallpaper) -> URL? {
        guard case .library(let location) = source else { return nil }
        switch wallpaper.kind {
        case .video: return location.url(for: wallpaper.optimisedCopy)
        case .scene: return hoverPreviewURL(for: wallpaper)
        }
    }

    private func drawnPoster(for id: WallpaperID) -> Image {
        if let image = drawn[id] { return image }
        let image = DrawnPoster.image(seed: Self.seed(for: id))
        drawn[id] = image
        return image
    }

    /// The same wallpaper draws the same picture on every run: FNV-1a over the UUID's bytes.
    static func seed(for id: WallpaperID) -> Int {
        let bytes = withUnsafeBytes(of: id.uuid.uuid) { Array($0) }
        let hash = bytes.reduce(UInt64(0xCBF2_9CE4_8422_2325)) { ($0 ^ UInt64($1)) &* 0x0000_0100_0000_01B3 }
        return Int(truncatingIfNeeded: hash)
    }
}
