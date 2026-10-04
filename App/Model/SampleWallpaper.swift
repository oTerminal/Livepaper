import AVFoundation
import Foundation
import LivepaperImport

/// A loop that ships in the app's `Samples` folder, offered on
/// onboarding's first card and imported as any file is. Their sources and
/// licences are in `Resources/Samples/PROVENANCE.md`, which ships beside them.
struct SampleWallpaper: Identifiable, Hashable {
    let url: URL

    var id: URL { url }

    /// What the wallpaper will be called: its file's name, as an import names it.
    var title: String { url.deletingPathExtension().lastPathComponent }

    /// The bundle's samples, by name; none when the folder is missing, and the
    /// first card then offers only a drop and the Open panel.
    static func bundled(in bundle: Bundle = .main) -> [SampleWallpaper] {
        guard let folder = bundle.resourceURL?.appending(path: "Samples", directoryHint: .isDirectory),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
        else { return [] }
        return files
            .filter { importableExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map(SampleWallpaper.init)
    }

    /// A frame from the start of the loop, at a tile's size: the poster the
    /// card shows until the pointer rests on it and it plays.
    @concurrent
    static func poster(of url: URL) async -> CGImage? {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 640, height: 400)
        return try? await generator.image(at: .zero).image
    }
}
