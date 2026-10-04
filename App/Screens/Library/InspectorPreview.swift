import DesignSystem
import LivepaperCore
import SwiftUI

/// The inspector's preview: the wallpaper in a frame the shape of the first
/// display, fitted by the presentation being edited, as the display would fit
/// it (`pictureRect`). The optimised copy plays over its poster, or a scene's
/// hover preview; in the fakes run there is no copy, and the
/// poster stays.
struct InspectorPreview: View {
    @Environment(AppModel.self) private var model
    let wallpaper: Wallpaper
    let presentation: Presentation
    let volume: Double
    let aspectRatio: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
        Color.black
            .aspectRatio(aspectRatio, contentMode: .fit)
            .overlay {
                GeometryReader { geometry in
                    let source = Size(width: Double(wallpaper.details.width), height: Double(wallpaper.details.height))
                    let picture = pictureRect(
                        for: presentation, source: source, surface: Size(width: geometry.size.width, height: geometry.size.height)
                    )
                    WallpaperPoster(wallpaper) { poster in
                        (poster ?? .posterLoading)
                            .resizable()
                            .frame(width: picture.size.width, height: picture.size.height)
                            .offset(x: picture.origin.x, y: picture.origin.y)
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
                }
            }
            .overlay {
                if let copy = model.art.inspectorPreviewURL(for: wallpaper) {
                    PreviewPlayerView(url: copy, presentation: presentation, volume: volume)
                }
            }
            .clipShape(shape)
            .imageOutline(shape)
            .accessibilityHidden(true)
    }
}

#Preview("Fill and Fit") {
    let model = AppModel.preview()
    let wallpaper = model.library.wallpapers[7]
    HStack(spacing: Spacing.large) {
        InspectorPreview(wallpaper: wallpaper, presentation: Presentation(fit: .fill), volume: 0, aspectRatio: 16 / 10)
        InspectorPreview(wallpaper: wallpaper, presentation: Presentation(fit: .fit), volume: 0, aspectRatio: 16 / 10)
        InspectorPreview(
            wallpaper: wallpaper, presentation: Presentation(fit: .fill, zoom: 2, pan: Point(x: 0.2, y: 0)), volume: 0, aspectRatio: 16 / 10
        )
    }
    .frame(width: 900)
    .padding(Spacing.large)
    .environment(model)
}
