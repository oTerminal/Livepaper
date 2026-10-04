import Foundation

/// A value in a scene's JSON, as Wallpaper Engine writes it: a number, a string
/// of numbers ("960.0 540.0 0.0"), an array, or one of those wrapped in an object
/// that says where it comes from:
///
///     {"value": …, "user": "rain"}                                bound to a user property
///     {"value": …, "user": {"name": "screen", "condition": "3"}}   true while the property is "3"
///     {"value": …, "script": "…"}                                 set by a script, which is not run
///     {"value": …, "animation": {…}}                              keyframed, not played
///
/// A user property takes the item's own default, from its project's
/// `general.properties`, which is what Wallpaper Engine shows before the user
/// changes anything. Everything else takes the stored value.
struct SceneValues: Sendable {
    /// The item's user properties by name, each its default value.
    private let properties: [String: SendableJSON]

    init(project: [String: Any] = [:]) {
        let general = project["general"] as? [String: Any] ?? [:]
        let declared = general["properties"] as? [String: Any] ?? [:]
        var properties: [String: SendableJSON] = [:]
        for (name, property) in declared {
            if let value = (property as? [String: Any])?["value"] { properties[name] = SendableJSON(value) }
        }
        self.properties = properties
    }

    /// The plain value behind any wrapping; nil for JSON null or nothing.
    func unwrap(_ any: Any?) -> Any? {
        unwrap(any, depth: 0)
    }

    /// As many wrappings as a value is unwrapped through. Wallpaper Engine's
    /// own nest two or three deep; a property bound to itself would never end.
    private static let deepestWrapping = 8

    private func unwrap(_ any: Any?, depth: Int) -> Any? {
        guard let object = any as? [String: Any] else { return any is NSNull ? nil : any }
        guard depth < Self.deepestWrapping else { return nil }
        if let user = object["user"] {
            if let name = user as? String, let value = properties[name]?.value { return unwrap(value, depth: depth + 1) }
            if let binding = user as? [String: Any], let name = binding["name"] as? String,
               let condition = binding["condition"], let value = properties[name]?.value {
                return Self.text(of: value) == Self.text(of: condition)
            }
        }
        return object["value"].flatMap { unwrap($0, depth: depth + 1) }
    }

    func floats(_ any: Any?) -> [Float]? {
        switch unwrap(any) {
        case let number as NSNumber:
            return [number.floatValue]
        case let text as String:
            let parts = text.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Float($0) }
            return parts.isEmpty ? nil : parts
        case let array as [Any]:
            let parts = array.compactMap { ($0 as? NSNumber)?.floatValue }
            return parts.isEmpty ? nil : parts
        default:
            return nil
        }
    }

    func float(_ any: Any?, _ fallback: Float) -> Float {
        floats(any)?.first ?? fallback
    }

    /// Three numbers; one number fills all three, and a short list keeps the fallback's last.
    func vector(_ any: Any?, _ fallback: SIMD3<Float>) -> SIMD3<Float> {
        guard let values = floats(any), let first = values.first else { return fallback }
        guard values.count > 1 else { return SIMD3(repeating: first) }
        return SIMD3(first, values[1], values.count > 2 ? values[2] : fallback.z)
    }

    func bool(_ any: Any?, _ fallback: Bool) -> Bool {
        switch unwrap(any) {
        case let number as NSNumber: number.boolValue
        case let text as String: text == "true" || text == "1"
        default: fallback
        }
    }

    func int(_ any: Any?) -> Int? {
        switch unwrap(any) {
        case let number as NSNumber: number.intValue
        case let text as String: Int(text)
        default: nil
        }
    }

    /// A property's value as its condition would be written: combos are strings, and so are their conditions.
    private static func text(of value: Any) -> String {
        switch value {
        case let text as String: text
        case let number as NSNumber where CFGetTypeID(number) == CFBooleanGetTypeID(): number.boolValue ? "true" : "false"
        case let number as NSNumber: number.stringValue
        default: "\(value)"
        }
    }
}

/// A value out of `JSONSerialization`, which is immutable once made.
private struct SendableJSON: @unchecked Sendable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }
}
