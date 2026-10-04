import Foundation
import simd

// A scene's JSON as it is drawn: the objects in order, each image layer with its
// material and effects, the particle systems and the sounds. Read from the
// samples; the meaning of every field is
// inferred from them, not documented by Wallpaper Engine.

/// One material pass (`materials/*.json`, `passes[0]`), with the scene's overrides merged in.
public struct SceneMaterial: @unchecked Sendable {
    public var shader: String
    /// Texture names by slot: `masks/foo` is `materials/masks/foo.tex`, and `_rt_…` names a render target.
    public var textures: [String?]
    /// Combos by upper-case name.
    public var combos: [String: Int]
    /// "normal" (replace), "translucent" or "additive".
    public var blending: String
    /// Shader constants by the uniform annotation's "material" name. Values from JSON, read with `SceneValues`.
    public var constants: [String: Any]

    init(json: [String: Any], values: SceneValues) {
        shader = json["shader"] as? String ?? ""
        textures = (json["textures"] as? [Any])?.map { $0 as? String } ?? []
        combos = Self.combos(json["combos"], values)
        blending = json["blending"] as? String ?? "normal"
        constants = json["constantshadervalues"] as? [String: Any] ?? [:]
    }

    init(shader: String, blending: String) {
        self.shader = shader
        textures = []
        combos = [:]
        self.blending = blending
        constants = [:]
    }

    private static func combos(_ any: Any?, _ values: SceneValues) -> [String: Int] {
        var combos: [String: Int] = [:]
        for (name, value) in (any as? [String: Any]) ?? [:] {
            if let number = values.int(value) { combos[name.uppercased()] = number }
        }
        return combos
    }

    /// The scene's overrides for this pass: its textures where it names one, its combos and its constants.
    mutating func apply(scene json: [String: Any], values: SceneValues) {
        for (slot, value) in ((json["textures"] as? [Any]) ?? []).enumerated() {
            guard let name = value as? String else { continue }
            while textures.count <= slot { textures.append(nil) }
            textures[slot] = name
        }
        for (name, value) in Self.combos(json["combos"], values) { combos[name] = value }
        for (name, value) in (json["constantshadervalues"] as? [String: Any]) ?? [:] { constants[name] = value }
    }
}

/// One pass of an effect: a material drawn into a target, or a command such as `copy`.
public struct EffectPass: Sendable {
    public var material: SceneMaterial?
    public var command: String?
    /// The named render target drawn into; nil for the effect's next ping-pong target.
    public var target: String?
    public var source: String?
    /// Slots given "previous" (the effect's input) or a named render target.
    public var binds: [(name: String, slot: Int)] = []
}

/// A render target an effect declares (`fbos`), a fraction of the layer's size.
public struct EffectTarget: Sendable {
    public let name: String
    /// The layer's size is divided by this.
    public let scale: Int
    public let format: String
}

public struct SceneEffect: Sendable {
    public let file: String
    public let name: String
    public let isVisible: Bool
    public let passes: [EffectPass]
    public let targets: [EffectTarget]
}

/// Where an object sits in the scene: its origin in scene units, its scale,
/// and its angles in radians, of which a 2D scene turns only about z.
public struct SceneTransform: Sendable {
    public var origin = SIMD3<Float>.zero
    public var scale = SIMD3<Float>.one
    public var angles = SIMD3<Float>.zero
    /// How far the camera's parallax moves the object, along x and y.
    public var parallaxDepth = SIMD2<Float>.one

    init(_ object: [String: Any], values: SceneValues) {
        origin = values.vector(object["origin"], .zero)
        scale = values.vector(object["scale"], .one)
        angles = values.vector(object["angles"], .zero)
        let depth = values.floats(object["parallaxDepth"]) ?? [1, 1]
        parallaxDepth = SIMD2(depth.first ?? 1, depth.count > 1 ? depth[1] : depth.first ?? 1)
    }
}

public struct SceneLayer: Sendable {
    public enum Kind: String, Sendable {
        /// A texture, through its model's material.
        case image
        /// `models/util/fullscreenlayer.json`: effects over everything drawn so far.
        case fullscreen
        /// `models/util/composelayer.json`: effects over what is behind the layer's rectangle.
        case compose
        /// `models/util/solidlayer.json`: a flat colour.
        case solid
    }

    public let id: Int
    public let name: String
    public let kind: Kind
    public let isVisible: Bool
    public let transform: SceneTransform
    public let size: SIMD2<Float>
    public let alpha: Float
    public let colour: SIMD3<Float>
    public let brightness: Float
    public let material: SceneMaterial?
    /// The puppet (`.mdl`) the layer's model names, if it is one.
    public let puppet: String?
    public let effects: [SceneEffect]
}

public struct SceneParticles: @unchecked Sendable {
    public let id: Int
    public let name: String
    public let file: String
    public let isVisible: Bool
    public let transform: SceneTransform
    /// `instanceoverride`: count, rate, size, alpha, lifetime, speed, colorn.
    public let overrides: [String: Any]
}

public struct SceneSound: Sendable {
    public let id: Int
    public let name: String
    public let files: [String]
    public let isVisible: Bool
    /// 0 to 1, before the wallpaper's own volume.
    public let volume: Float
    /// "loop", or "single" and the like: played once.
    public let playback: String
    /// Starts silent, for a script to start it.
    public let startsSilent: Bool
}

public enum SceneObject: Sendable {
    case layer(SceneLayer)
    case particles(SceneParticles)
    case sound(SceneSound)
    /// Text, lights, models and anything else not drawn: their keys, for the log.
    case other(id: Int, name: String, keys: [String])
}

/// A scene as it is drawn: `project.json`, then the scene's JSON in the
/// package, then the models, materials and effects it names.
public struct SceneDocument: @unchecked Sendable {
    public let files: SceneFiles
    public let width: Float
    public let height: Float
    public let clearColour: SIMD3<Float>
    /// `general`, for bloom, the camera and the like.
    public let general: [String: Any]
    /// Back to front.
    public private(set) var objects: [SceneObject] = []
    /// What could not be read, and where: drawn without.
    public private(set) var problems: [String] = []

    var values: SceneValues { files.values }

    public init(folder: URL) throws {
        try self.init(files: SceneFiles(folder: folder))
    }

    public init(files: SceneFiles) throws(SceneReadError) {
        self.files = files
        let values = files.values
        let scene = try files.json(files.sceneFile)
        general = scene["general"] as? [String: Any] ?? [:]
        let projection = general["orthogonalprojection"] as? [String: Any]
        width = max(1, values.float(projection?["width"], 1920))
        height = max(1, values.float(projection?["height"], 1080))
        clearColour = values.vector(general["clearcolor"], .zero)

        for object in scene["objects"] as? [[String: Any]] ?? [] {
            let id = values.int(object["id"]) ?? -1
            let name = object["name"] as? String ?? ""
            if let model = object["image"] as? String {
                do {
                    objects.append(.layer(try layer(object, id: id, name: name, model: model)))
                } catch {
                    problems.append("object \(id) \(name): \(model) cannot be read")
                }
            } else if let file = object["particle"] as? String {
                objects.append(.particles(SceneParticles(
                    id: id, name: name, file: file, isVisible: values.bool(object["visible"], true),
                    transform: SceneTransform(object, values: values),
                    overrides: object["instanceoverride"] as? [String: Any] ?? [:]
                )))
            } else if let sounds = object["sound"] as? [String] {
                objects.append(.sound(SceneSound(
                    id: id, name: name, files: sounds, isVisible: values.bool(object["visible"], true),
                    volume: values.float(object["volume"], 1), playback: object["playbackmode"] as? String ?? "loop",
                    startsSilent: values.bool(object["startsilent"], false)
                )))
            } else {
                objects.append(.other(id: id, name: name, keys: object.keys.sorted()))
            }
        }
    }

    public var layers: [SceneLayer] {
        objects.compactMap { if case .layer(let layer) = $0 { layer } else { nil } }
    }

    private mutating func layer(_ object: [String: Any], id: Int, name: String, model: String) throws(SceneReadError) -> SceneLayer {
        var kind = SceneLayer.Kind.image
        var material: SceneMaterial?
        var puppet: String?
        switch model {
        case "models/util/fullscreenlayer.json": kind = .fullscreen
        case "models/util/composelayer.json": kind = .compose
        case "models/util/solidlayer.json": kind = .solid
        default:
            let json = try files.json(model)
            puppet = json["puppet"] as? String
            guard let path = json["material"] as? String else { throw .malformedScene }
            material = try firstPass(of: path)
        }
        var effects: [SceneEffect] = []
        for effect in object["effects"] as? [[String: Any]] ?? [] {
            guard let file = effect["file"] as? String else { continue }
            do {
                effects.append(try self.effect(effect, file: file))
            } catch {
                problems.append("effect \(file) on \(name) cannot be read")
            }
        }
        let size = values.floats(object["size"]) ?? []
        return SceneLayer(
            id: id, name: name, kind: kind,
            isVisible: values.bool(object["visible"], true),
            transform: SceneTransform(object, values: values),
            size: SIMD2(size.first ?? 0, size.count > 1 ? size[1] : 0),
            alpha: values.float(object["alpha"], 1),
            colour: values.vector(object["color"], .one),
            brightness: values.float(object["brightness"], 1),
            material: material, puppet: puppet, effects: effects
        )
    }

    func firstPass(of path: String) throws(SceneReadError) -> SceneMaterial {
        guard let pass = (try files.json(path)["passes"] as? [[String: Any]])?.first else { throw .malformedScene }
        return SceneMaterial(json: pass, values: values)
    }

    private func effect(_ object: [String: Any], file: String) throws(SceneReadError) -> SceneEffect {
        let definition = try files.json(file)
        // The scene's passes line up with the effect's material passes; commands have none.
        let scenePasses = object["passes"] as? [[String: Any]] ?? []
        var passes: [EffectPass] = []
        var materialIndex = 0
        for json in definition["passes"] as? [[String: Any]] ?? [] {
            var pass = EffectPass()
            pass.command = json["command"] as? String
            pass.target = json["target"] as? String
            pass.source = json["source"] as? String
            pass.binds = (json["bind"] as? [[String: Any]] ?? []).compactMap { bind in
                guard let name = bind["name"] as? String, let slot = values.int(bind["index"]) else { return nil }
                return (name, slot)
            }
            if let path = json["material"] as? String {
                var material = try firstPass(of: path)
                if materialIndex < scenePasses.count { material.apply(scene: scenePasses[materialIndex], values: values) }
                materialIndex += 1
                pass.material = material
            }
            passes.append(pass)
        }
        let targets = (definition["fbos"] as? [[String: Any]] ?? []).map { target in
            EffectTarget(
                name: target["name"] as? String ?? "", scale: values.int(target["scale"]) ?? 1,
                format: target["format"] as? String ?? "rgba8888"
            )
        }
        let name = (file as NSString).deletingLastPathComponent.components(separatedBy: "/").last ?? file
        return SceneEffect(file: file, name: name, isVisible: values.bool(object["visible"], true), passes: passes, targets: targets)
    }

    /// Reads a value of the scene as it is drawn: its user properties at the item's defaults.
    public func float(_ any: Any?, _ fallback: Float) -> Float { values.float(any, fallback) }
    public func floats(_ any: Any?) -> [Float]? { values.floats(any) }
    public func bool(_ any: Any?, _ fallback: Bool) -> Bool { values.bool(any, fallback) }
    public func vector(_ any: Any?, _ fallback: SIMD3<Float>) -> SIMD3<Float> { values.vector(any, fallback) }
}
