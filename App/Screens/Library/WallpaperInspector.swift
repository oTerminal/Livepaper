import DesignSystem
import LivepaperCore
import SwiftUI

/// The inspector for the selected wallpaper: its preview with the fit mode
/// over it, its name and favourite, Set on Display, the focal point, pan and
/// zoom, volume, its details, and Delete. The preview follows every edit at
/// once; the library and the displays once the edit settles (`editSettles`).
struct WallpaperInspector: View {
    @Environment(AppModel.self) private var model
    let wallpaper: Wallpaper

    @State private var name: String
    @FocusState private var isNameFocused: Bool

    init(wallpaper: Wallpaper) {
        self.wallpaper = wallpaper
        _name = State(initialValue: wallpaper.name)
    }

    private var imageSize: CGSize {
        CGSize(width: wallpaper.details.width, height: wallpaper.details.height)
    }

    var body: some View {
        let presentation = model.presentation(of: wallpaper)
        let assignment = Assignment.wallpaper(wallpaper.id)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.extraLarge) {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    InspectorPreview(
                        wallpaper: wallpaper,
                        presentation: presentation,
                        volume: model.previewVolume(of: wallpaper),
                        aspectRatio: model.previewAspectRatio
                    )
                    .overlay(alignment: .bottom) {
                        FitModePicker("Fit mode", selection: edit(\.fit), options: Self.fitModes)
                            .padding(Spacing.small)
                    }
                    nameRow
                    SetOnDisplayButton(
                        targets: model.setOnDisplayTargets(for: assignment),
                        state: model.setOnDisplayState(for: assignment)
                    ) { target in
                        model.setOnDisplay(assignment, target: target)
                    }
                }

                InspectorSection("Focal Point") {
                    WallpaperPoster(wallpaper) { poster in
                        FocalPointEditor(image: poster ?? .posterLoading, imageSize: imageSize, focalPoint: focalPoint)
                    }
                    .aspectRatio(imageSize.width / max(imageSize.height, 1), contentMode: .fit)
                }

                InspectorSection("Pan and Zoom") {
                    WallpaperPoster(wallpaper) { poster in
                        PanZoomEditor(
                            image: poster ?? .posterLoading,
                            imageSize: imageSize,
                            frameAspectRatio: model.previewAspectRatio,
                            zoom: zoom,
                            pan: edit(\.panSize),
                            focalPoint: presentation.focalPoint.unitPoint
                        )
                    }
                }

                InspectorSection("Volume", caption: "Mute silences every display.") {
                    VolumeSlider(volume: volume, isMuted: isMuted)
                }

                InspectorSection("Details") {
                    DetailsList(rows: detailsRows)
                }

                // Space on the focused button is a key press: the toast and the grid change without motion.
                Button("Delete", role: .destructive) {
                    withoutAnimationIfKeyPress { model.delete(wallpaper.id) }
                }
                .controlSize(.large)
            }
            .padding(Spacing.large)
        }
        .onChange(of: wallpaper.name) { _, renamed in
            if !isNameFocused { name = renamed }
        }
    }

    /// The name, renamed when Return is pressed or the field is left; an empty one puts the old name back.
    private var nameRow: some View {
        HStack(spacing: Spacing.tight) {
            TextField("Name", text: $name)
                .textFieldStyle(.plain)
                .font(.title3.weight(.semibold))
                .focused($isNameFocused)
                .onSubmit(commitName)
                .onChange(of: isNameFocused) { _, isFocused in
                    if !isFocused { commitName() }
                }
                .help("Rename")
            Spacer(minLength: 0)
            FavouriteToggle(isOn: Binding { wallpaper.isFavourite } set: { model.setFavourite($0, for: wallpaper.id) })
        }
    }

    /// Core decides the name, and the field shows what it decided: the name as
    /// kept, or the old one back when it was refused.
    private func commitName() {
        guard model.rename(wallpaper.id, to: name), let renamed = model.library[wallpaper.id]?.name else {
            name = wallpaper.name
            return
        }
        name = renamed
    }

    // MARK: Bindings to the edit in progress

    /// One part of the presentation, as the inspector is editing it.
    private func edit<Value>(_ part: WritableKeyPath<Presentation, Value>) -> Binding<Value> {
        Binding {
            model.presentation(of: wallpaper)[keyPath: part]
        } set: { value in
            model.editPresentation(of: wallpaper.id) { $0[keyPath: part] = value }
        }
    }

    private var focalPoint: Binding<UnitPoint> {
        Binding {
            model.presentation(of: wallpaper).focalPoint.unitPoint
        } set: { point in
            model.editPresentation(of: wallpaper.id) { $0.focalPoint = Point(point) }
        }
    }

    private var zoom: Binding<CGFloat> {
        Binding {
            CGFloat(model.presentation(of: wallpaper).zoom)
        } set: { zoom in
            model.editPresentation(of: wallpaper.id) { $0.zoom = Double(zoom) }
        }
    }

    private var volume: Binding<Double> {
        Binding { model.volume(of: wallpaper) } set: { model.editVolume($0, of: wallpaper.id) }
    }

    /// The app's one mute: there is no mute per wallpaper.
    private var isMuted: Binding<Bool> {
        Binding { model.isMuted } set: { model.setMuted($0) }
    }

    // MARK: Words

    static let fitModes = [
        FitModeOption(value: FitMode.fill, title: "Fill", systemImage: "arrow.up.left.and.arrow.down.right"),
        FitModeOption(value: FitMode.fit, title: "Fit", systemImage: "arrow.down.right.and.arrow.up.left"),
        FitModeOption(value: FitMode.stretch, title: "Stretch", systemImage: "arrow.left.and.right"),
    ]

    /// Core says which rows: a scene's say what it is and have no length or codec.
    private var detailsRows: [DetailsRow] {
        let details = wallpaper.details
        return wallpaper.detailsShown.map { detail in
            switch detail {
            case .kind: DetailsRow(label: "Kind", value: wallpaper.kind.words)
            case .resolution: DetailsRow(label: "Resolution", value: details.resolutionWords)
            case .length: DetailsRow(label: "Length", value: details.lengthWords)
            case .frameRate: DetailsRow(label: "Frame rate", value: details.frameRateWords)
            case .codec: DetailsRow(label: "Codec", value: details.codecWords)
            case .size: DetailsRow(label: "Size", value: Int64(details.byteCount).formatted(.byteCount(style: .file)))
            case .imported: DetailsRow(label: "Imported", value: wallpaper.importedAt.formatted(date: .abbreviated, time: .shortened))
            }
        }
    }
}

#Preview("Wallpaper inspector") {
    let model = AppModel.preview()
    WallpaperInspector(wallpaper: model.library.wallpapers[0])
        .frame(width: 320, height: 900)
        .environment(model)
}
