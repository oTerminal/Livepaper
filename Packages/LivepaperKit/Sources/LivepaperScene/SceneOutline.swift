import Foundation
import LivepaperCore

/// What an import needs to know of a scene, read from its JSON and the files
/// that JSON leads to inside the package.
public struct SceneOutline: Equatable, Sendable {
    /// The size the scene is laid out in, from `general.orthogonalprojection`.
    /// Nil when it has none: a scene in perspective, or one that sizes itself to the display.
    public var size: Size?
    /// For a GIF scene, the package's path of the one texture that is the
    /// whole scene; nil for any other scene.
    public var spriteSheet: String?
    /// What shows where the scene draws nothing: `general.clearcolor`, 0 to 1.
    public var clearColour: [Double]

    public init(size: Size?, spriteSheet: String?, clearColour: [Double] = [0, 0, 0]) {
        self.size = size
        self.spriteSheet = spriteSheet
        self.clearColour = clearColour
    }
}

/// Reads the outline of the scene whose JSON is `sceneFile` in `package`.
///
/// A GIF scene is one image layer that covers the scene exactly
/// as it is: no effects, no particles or anything else beside it, nothing that
/// moves, tints or fades it, one material pass with one texture. Whether that
/// texture really is a sprite sheet is the texture's to say (`SpriteSheet`).
public func readSceneOutline(of sceneFile: String, in package: ScenePackage) throws(SceneReadError) -> SceneOutline {
    let scene = try sceneJSON(package.require(sceneFile))
    let general = scene["general"] as? [String: Any] ?? [:]
    let size = orthogonalSize(general["orthogonalprojection"])
    let clearColour = numbers(general["clearcolor"]).flatMap { $0.count == 3 ? $0 : nil } ?? [0, 0, 0]
    return SceneOutline(size: size, spriteSheet: size.flatMap { spriteSheet(of: scene, size: $0, in: package) }, clearColour: clearColour)
}

// MARK: The GIF-scene rule

private func spriteSheet(of scene: [String: Any], size: Size, in package: ScenePackage) -> String? {
    let general = scene["general"] as? [String: Any] ?? [:]
    // A scene-wide effect would be missing from the frames.
    guard general["bloom"] as? Bool != true, general["camerashake"] as? Bool != true else { return nil }
    guard let objects = scene["objects"] as? [[String: Any]], objects.count == 1, let layer = objects.first else { return nil }
    guard isPlainImage(layer), covers(layer, size) else { return nil }

    guard
        let modelPath = layer["image"] as? String,
        let model = try? sceneJSON(package.require(modelPath)), model["puppet"] == nil,
        let materialPath = model["material"] as? String,
        let material = try? sceneJSON(package.require(materialPath)),
        let passes = material["passes"] as? [[String: Any]], passes.count == 1, let pass = passes.first,
        (pass["shader"] as? String)?.hasPrefix("genericimage") == true,
        let textures = pass["textures"] as? [Any], textures.count == 1, let texture = textures.first as? String
    else { return nil }
    let path = "materials/\(texture).tex"
    return package.entry(path) == nil ? nil : path
}

/// An image layer and nothing else: no effects, nothing a user or a script
/// switches on and off.
private func isPlainImage(_ layer: [String: Any]) -> Bool {
    let others = ["particle", "sound", "text", "model", "light", "animationlayers"]
    guard layer["image"] is String, others.allSatisfy({ layer[$0] == nil }) else { return false }
    guard (layer["effects"] as? [Any])?.isEmpty ?? (layer["effects"] == nil) else { return false }
    return layer["visible"] == nil || layer["visible"] as? Bool == true
}

/// Exactly over the scene: its size, centred, untouched by scale, angle,
/// colour, brightness or alpha. A value bound to a user property is not a plain value, so it fails.
private func covers(_ layer: [String: Any], _ size: Size) -> Bool {
    func near(_ values: [Double]?, _ expected: [Double]) -> Bool {
        guard let values, values.count >= expected.count else { return false }
        return zip(values, expected).allSatisfy { abs($0 - $1) < 0.5 }
    }
    func plain(_ key: String, _ expected: [Double]) -> Bool {
        layer[key] == nil || near(numbers(layer[key]), expected)
    }
    return near(numbers(layer["size"]), [size.width, size.height])
        && near(numbers(layer["origin"]), [size.width / 2, size.height / 2])
        && plain("scale", [1, 1, 1]) && plain("angles", [0, 0, 0]) && plain("color", [1, 1, 1])
        && plain("alpha", [1]) && plain("brightness", [1])
}

// MARK: Reading JSON

/// A JSON object, with or without the byte-order mark Windows programs put first.
func sceneJSON(_ data: Data) throws(SceneReadError) -> [String: Any] {
    let bom = Data([0xEF, 0xBB, 0xBF])
    let text = data.starts(with: bom) ? data.dropFirst(bom.count) : data
    guard let object = try? JSONSerialization.jsonObject(with: text) as? [String: Any] else { throw .malformedScene }
    return object
}

/// Wallpaper Engine writes vectors as strings of numbers ("960.00000 540.00000 0.00000") and scalars as numbers.
private func numbers(_ value: Any?) -> [Double]? {
    // `as? Bool` would take a 1 or a 0 for a Boolean; only a JSON true or false is one.
    if let number = value as? NSNumber { return CFGetTypeID(number) == CFBooleanGetTypeID() ? nil : [number.doubleValue] }
    guard let text = value as? String else { return nil }
    let values = text.split(whereSeparator: \.isWhitespace).map { Double($0) }
    return values.isEmpty || values.contains(nil) ? nil : values.compactMap(\.self)
}

private func orthogonalSize(_ value: Any?) -> Size? {
    guard
        let projection = value as? [String: Any],
        let width = numbers(projection["width"])?.first, let height = numbers(projection["height"])?.first,
        width >= 1, height >= 1, width <= 16384, height <= 16384
    else { return nil }
    return Size(width: width.rounded(), height: height.rounded())
}
