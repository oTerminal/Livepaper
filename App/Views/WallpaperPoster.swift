import DesignSystem
import LivepaperCore
import SwiftUI

/// A wallpaper's poster as an `Image`, for a design-system component, in either
/// run: read from the library at the size it is laid out (`PosterImage`), or, in
/// the fakes run, drawn from the wallpaper's identifier. Nil while it loads.
///
///     WallpaperPoster(wallpaper) { poster in
///         WallpaperTile(id: wallpaper.id, poster: poster ?? placeholder, title: wallpaper.name, …)
///     }
///
/// Where a component takes several posters at once, such as `RecentsStrip`,
/// `AppModel.art.poster(for:size:)` gives each one without a view.
struct WallpaperPoster<Content: View>: View {
    @Environment(AppModel.self) private var model
    private let wallpaper: Wallpaper
    private let content: (Image?) -> Content

    init(_ wallpaper: Wallpaper, @ViewBuilder content: @escaping (Image?) -> Content) {
        self.wallpaper = wallpaper
        self.content = content
    }

    var body: some View {
        if let url = model.art.posterURL(for: wallpaper) {
            PosterImage(url: url, revision: model.art.posterRevision(for: wallpaper), content: content)
        } else {
            content(model.art.poster(for: wallpaper, size: DrawnPoster.size))
        }
    }
}

extension WallpaperPoster where Content == PosterFill {
    /// The poster filling the frame it is given, cropped to it.
    init(_ wallpaper: Wallpaper) {
        self.init(wallpaper) { PosterFill(image: $0) }
    }
}

extension Image {
    /// Where a poster goes while it is read, for a component that takes an
    /// `Image`: the quaternary fill, which follows the appearance it is drawn in,
    /// never a symbol stretched to fill.
    static let posterLoading = Image(size: CGSize(width: 16, height: 10)) { context in
        context.fill(Path(CGRect(x: 0, y: 0, width: 16, height: 10)), with: .style(.quaternary))
    }
}

#Preview {
    let model = AppModel.preview()
    HStack(spacing: Spacing.medium) {
        ForEach(model.library.wallpapers.prefix(3)) { wallpaper in
            WallpaperPoster(wallpaper)
                .aspectRatio(16 / 10, contentMode: .fit)
                .frame(width: 160)
                .clipShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
        }
    }
    .padding(Spacing.large)
    .environment(model)
}
