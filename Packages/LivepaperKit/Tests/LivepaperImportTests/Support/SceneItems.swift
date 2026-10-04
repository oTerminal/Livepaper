import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
import LivepaperImport
import LivepaperScene
import LivepaperTestSupport

/// An item's preview, as a Workshop item has one: a still or an animated GIF, square.
enum Preview {
    case still(side: Int, colour: SyntheticScene.Colour)
    case animated(side: Int, colours: [SyntheticScene.Colour])
}

extension TemporaryFolder {
    /// A scene item laid out as Wallpaper Engine lays one out: `project.json`,
    /// the package of `entries`, a preview, and the `shaders/` cache beside
    /// them. Every byte made here; nothing from the Workshop.
    @discardableResult
    func writeSceneItem(
        _ path: String, entries: [SyntheticScene.Entry], sceneFile: String = "scene.json", title: String? = "Lantern Street",
        preview: Preview? = .still(side: 48, colour: SyntheticScene.Colour(200, 120, 40))
    ) throws -> URL {
        let item = folder(path)
        let previewName = preview.map { if case .animated = $0 { "preview.gif" } else { "preview.jpg" } }
        var project: [String: Any] = ["file": sceneFile, "type": "scene", "tags": ["Unspecified"]]
        project["title"] = title
        project["preview"] = previewName
        let json = try JSONSerialization.data(withJSONObject: project, options: [.sortedKeys])
        try write(String(bytes: json, encoding: .utf8) ?? "", to: "\(path)/project.json")

        let package = file("\(path)/\(SceneFolder.itemPackage(for: sceneFile))")
        try SyntheticScene.package(entries).write(to: package)
        try write("DXBC", to: "\(path)/shaders/blobsSM40/0a1b2c.dxs")
        if let preview, let previewName {
            try writePicture(preview, to: file("\(path)/\(previewName)"))
        }
        return item
    }

    private func writePicture(_ preview: Preview, to url: URL) throws {
        switch preview {
        case .still(let side, let colour):
            try writeImages([solid(colour, side: side)], as: .jpeg, to: url)
        case .animated(let side, let colours):
            try writeImages(colours.map { solid($0, side: side) }, as: .gif, to: url)
        }
    }

    private func writeImages(_ images: [CGImage], as type: UTType, to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, images.count, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let frame = [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]] as CFDictionary
        for image in images {
            CGImageDestinationAddImage(destination, image, type == .gif ? frame : nil)
        }
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    }

    private func solid(_ colour: SyntheticScene.Colour, side: Int) -> CGImage {
        let context = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )
        context?.setFillColor(red: Double(colour.red) / 255, green: Double(colour.green) / 255, blue: Double(colour.blue) / 255, alpha: 1)
        context?.fill(CGRect(x: 0, y: 0, width: side, height: side))
        guard let image = context?.makeImage() else { preconditionFailure("no picture of \(side) pixels") }
        return image
    }
}

extension SyntheticScene {
    /// A scene of `width` by `height` that is no GIF scene: an image layer with an effect on it.
    static func liveScene(width: Int = 3840, height: Int = 2160, sceneFile: String = "scene.json") -> [Entry] {
        let layer = imageLayer(width: width, height: height, fields: ["effects": #"[{"file": "effects/waterripple/effect.json"}]"#])
        return [
            Entry(sceneFile, json: sceneJSON(width: width, height: height, layers: [layer])),
            Entry("models/background.json", json: #"{"material": "materials/background.json"}"#),
            Entry("materials/background.json", json: #"{"passes": [{"shader": "genericimage", "textures": ["background"]}]}"#),
            Entry("materials/background.tex", Data("TEXV0005".utf8)),
        ]
    }
}
