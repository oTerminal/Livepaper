import Foundation

/// What a scene's shader says about itself in comments: its `// [COMBO] {…}`
/// lines, and the JSON after a uniform
/// (`uniform float g_Scale; // {"material":"scale","default":1}`), which gives
/// the uniform's key among the material's constants and its default. Read from
/// the samples; nothing about it is documented.
public struct ShaderAnnotations {
    /// A preprocessor switch the shader declares, with its default.
    public struct Combo {
        public let name: String
        public let defaultValue: Int
        public let json: [String: Any]
    }

    public struct Uniform {
        public let type: String
        public let name: String
        public let arrayCount: Int?
        public let json: [String: Any]?

        /// The key among the material's and the scene's `constantshadervalues`.
        public var materialKey: String? { json?["material"] as? String }
        public var defaultValue: Any? { json?["default"] }

        /// The default as numbers: a number, a string of them ("1 1 1") or an array.
        public var defaultNumbers: [Float]? {
            switch defaultValue {
            case let number as NSNumber:
                return [number.floatValue]
            case let text as String:
                let parts = text.split { $0 == " " || $0 == "," }.compactMap { Float($0) }
                return parts.isEmpty ? nil : parts
            case let array as [Any]:
                let parts = array.compactMap { ($0 as? NSNumber)?.floatValue }
                return parts.isEmpty ? nil : parts
            default:
                return nil
            }
        }
    }

    public private(set) var combos: [Combo] = []
    public private(set) var uniforms: [String: Uniform] = [:]
    /// Uniform names in the order they were first declared.
    public private(set) var uniformOrder: [String] = []
    /// Declared but switched off by the shader's author (`[COMBO_OFF]`, `[OFF_COMBO]`): left undefined.
    public private(set) var disabledCombos: [String] = []
    /// Annotation lines whose JSON could not be read, even repaired.
    public private(set) var badJSON: [String] = []

    public init() {}

    /// Both stages' sources, vertex first: a later annotated declaration of a
    /// uniform wins over an earlier bare one.
    public init(sources: [String]) {
        for source in sources { read(source) }
    }

    // One annotation comment on a line of its own, and one loose uniform with an optional comment after it.
    private static let comboLine = wellFormed(#"^\s*//\s*\[(\w+)\]\s*(\{.*\})\s*$"#)
    private static let uniformLine = wellFormed(
        #"^\s*uniform\s+(?:(?:lowp|mediump|highp)\s+)?(\w+)\s+(\w+)\s*(?:\[\s*(\d+)\s*\])?\s*;\s*(?://\s*(.*))?$"#
    )

    private mutating func read(_ source: String) {
        // Split on any line break: a CRLF file is one Character per break, so splitting on "\n" finds none.
        for line in source.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline) {
            let text = String(line)
            let whole = text as NSString
            let range = NSRange(location: 0, length: whole.length)
            if let match = Self.comboLine.firstMatch(in: text, range: range) {
                readCombo(text, tag: match.group(1, in: whole) ?? "", json: match.group(2, in: whole) ?? "")
            } else if let match = Self.uniformLine.firstMatch(in: text, range: range) {
                let (type, name) = (match.group(1, in: whole) ?? "", match.group(2, in: whole) ?? "")
                let count = match.group(3, in: whole).flatMap { Int($0) }
                readUniform(text, type: type, name: name, count: count, comment: match.group(4, in: whole))
            }
        }
    }

    /// `[COMBO]` declares one; any other tag, `[COMBO_OFF]` and the like, switches one off.
    private mutating func readCombo(_ line: String, tag: String, json text: String) {
        guard let json = Self.json(text) else {
            badJSON.append(line)
            return
        }
        let name = json["combo"] as? String ?? "?"
        guard tag == "COMBO" else {
            disabledCombos.append(name)
            return
        }
        if !combos.contains(where: { $0.name == name }) {
            combos.append(Combo(name: name, defaultValue: (json["default"] as? NSNumber)?.intValue ?? 0, json: json))
        }
    }

    /// A later declaration with an annotation wins over an earlier bare one, and not the other way round.
    private mutating func readUniform(_ line: String, type: String, name: String, count: Int?, comment: String?) {
        var json: [String: Any]?
        if let comment = comment?.trimmingCharacters(in: .whitespaces), comment.hasPrefix("{") {
            json = Self.json(comment)
            if json == nil { badJSON.append(line) }
        }
        if uniforms[name] == nil { uniformOrder.append(name) }
        if uniforms[name]?.json == nil || json != nil {
            uniforms[name] = Uniform(type: type, name: name, arrayCount: count, json: json)
        }
    }

    private static let leadingZero = wellFormed(#"(?<![\d.])0+(\d)"#)

    /// An annotation's JSON. Authors write what Wallpaper Engine's own parser
    /// takes, such as `"range":[0,01]`, which JSON does not: a number with a
    /// leading zero is read again without it.
    static func json(_ text: String) -> [String: Any]? {
        if let object = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] { return object }
        let range = NSRange(location: 0, length: (text as NSString).length)
        let repaired = leadingZero.stringByReplacingMatches(in: text, range: range, withTemplate: "$1")
        return (try? JSONSerialization.jsonObject(with: Data(repaired.utf8))) as? [String: Any]
    }

    /// Texture slots whose having a texture switches a combo on:
    /// `uniform sampler2D g_Texture1; // {"combo":"MASK"}`.
    public var textureCombos: [(slot: Int, combo: String)] {
        uniforms.values.compactMap { uniform in
            guard uniform.type.hasPrefix("sampler"), let combo = uniform.json?["combo"] as? String,
                  let slot = Self.textureSlot(uniform.name) else { return nil }
            return (slot, combo)
        }
    }

    /// `g_TextureN`'s N, the slot it is bound at.
    public static func textureSlot(_ name: String) -> Int? {
        guard name.hasPrefix("g_Texture") else { return nil }
        return Int(name.dropFirst("g_Texture".count))
    }

    /// The preprocessor defines for one program, sorted by name: the shader's
    /// `[COMBO]` defaults, then 1 or 0 for each texture-switched combo by
    /// whether its slot has a texture, then the combos the material and the
    /// scene set, each overriding what came before.
    public func defines(explicit: [String: Int], boundSlots: Set<Int>) -> [(name: String, value: Int)] {
        var values: [String: Int] = [:]
        for combo in combos { values[combo.name] = combo.defaultValue }
        for (slot, combo) in textureCombos { values[combo] = boundSlots.contains(slot) ? 1 : 0 }
        for (name, value) in explicit { values[name] = value }
        return values.sorted { $0.key < $1.key }.map { (name: $0.key, value: $0.value) }
    }
}

extension NSTextCheckingResult {
    /// What capture group `index` matched in `whole`, or nil when it took no part.
    func group(_ index: Int, in whole: NSString) -> String? {
        range(at: index).location == NSNotFound ? nil : whole.substring(with: range(at: index))
    }
}

/// A pattern written in this module, which is known to compile.
func wellFormed(_ pattern: String) -> NSRegularExpression {
    do {
        return try NSRegularExpression(pattern: pattern)
    } catch {
        preconditionFailure("\(pattern) does not compile: \(error)")
    }
}
