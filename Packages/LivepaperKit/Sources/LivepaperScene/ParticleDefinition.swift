import Foundation

/// A particle system's file (`particles/**/*.json`): its emitters,
/// initialisers, operators and renderers, a material, and child systems.
/// Parameters stay as JSON; the simulation reads the ones it knows.
public struct ParticleDefinition: @unchecked Sendable {
    public struct Component: @unchecked Sendable {
        public let name: String
        let parameters: [String: Any]
        let values: SceneValues

        public func float(_ key: String, _ fallback: Float) -> Float { values.float(parameters[key], fallback) }
        public func vector(_ key: String, _ fallback: SIMD3<Float>) -> SIMD3<Float> { values.vector(parameters[key], fallback) }
        public func has(_ key: String) -> Bool { parameters[key] != nil && !(parameters[key] is NSNull) }
        public func text(_ key: String) -> String? { parameters[key] as? String }
    }

    public struct Child: Sendable {
        public let file: String
        /// Nil for a second system beside the parent; "eventspawn" for a burst where a parent particle dies.
        public let type: String?
        public let maxCount: Int?
        public let origin: SIMD3<Float>
        public let scale: SIMD3<Float>
        public let probability: Float
    }

    public struct ControlPoint: Sendable {
        public let id: Int
        /// Non-zero: it follows the pointer.
        public let flags: Int
        public let offset: SIMD3<Float>
    }

    /// The most particles a system keeps alive, whatever its file or its object asks for.
    public static let mostParticles = 20_000

    public let file: String
    public let material: String
    public let maxCount: Int
    /// Seconds simulated before the first frame.
    public let startTime: Float
    public let emitters: [Component]
    public let initialisers: [Component]
    public let operators: [Component]
    public let renderers: [Component]
    public let children: [Child]
    public let controlPoints: [ControlPoint]
    /// "sequence" or "randomframe" when the texture is a sheet of frames; nil for one picture.
    public let animationMode: String?
    /// How many times a sequence plays over a particle's life.
    public let sequenceMultiplier: Float

    public init(files: SceneFiles, file: String) throws(SceneReadError) {
        let json = try files.json(file)
        let values = files.values
        self.file = file
        guard let material = json["material"] as? String else { throw .malformedScene }
        self.material = material
        maxCount = min(values.int(json["maxcount"]) ?? 100, Self.mostParticles)
        startTime = values.float(json["starttime"], 0)
        func list(_ key: String) -> [Component] {
            (json[key] as? [[String: Any]] ?? []).map { Component(name: $0["name"] as? String ?? "", parameters: $0, values: values) }
        }
        emitters = list("emitter")
        initialisers = list("initializer")
        operators = list("operator")
        renderers = list("renderer")
        children = (json["children"] as? [[String: Any]] ?? []).compactMap { child in
            guard let name = child["name"] as? String else { return nil }
            return Child(
                file: name, type: child["type"] as? String, maxCount: values.int(child["maxcount"]),
                origin: values.vector(child["origin"], .zero), scale: values.vector(child["scale"], .one),
                probability: values.float(child["probability"], 1)
            )
        }
        controlPoints = (json["controlpoint"] as? [[String: Any]] ?? []).map { point in
            ControlPoint(
                id: values.int(point["id"]) ?? 0, flags: values.int(point["flags"]) ?? 0, offset: values.vector(point["offset"], .zero)
            )
        }
        animationMode = json["animationmode"] as? String
        sequenceMultiplier = values.float(json["sequencemultiplier"], 1)
    }

    public func initialiser(_ name: String) -> Component? { initialisers.first { $0.name == name } }
    public func `operator`(_ name: String) -> Component? { operators.first { $0.name == name } }
}
