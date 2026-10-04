import Foundation

/// Takes out of a line what a diagnostics report must never say: where the
/// user's files are, who the user is, and what their wallpapers and files are
/// called.
///
/// - Every path goes, from its first slash, or its `~`, to the next space or
///   quote: `<path>`. The home folder goes with it, in full or as `~`, and so
///   do the folders under it, whose names nobody passed in. A space inside a
///   path ends it there, so the names below are taken out first.
/// - The user's short and full names and the Steam account's: `<user>`.
/// - Every wallpaper's name: `<wallpaper>`.
/// - The names of the library's files and of the source files imported: `<file>`.
/// - What the unified log hid as `<private>`: `<hidden>`.
///
/// A name goes wherever it stands as a word of its own, in any case: not
/// inside a longer word ("Sun" is kept in "Sunday"), but beside a slash, a dot
/// or a quote. The longer of two names is taken first, and a name that is a
/// placeholder's word does not break a placeholder: each is put in once the
/// rest is done.
public struct Redaction: Sendable {
    private let names: NSRegularExpression?
    /// Each name, folded, and what it is.
    private let kinds: [String: Placeholder]
    private let places: NSRegularExpression

    /// - Parameters:
    ///   - home: the home folder's path.
    ///   - userNames: the user's short and full names, and the Steam account's.
    ///   - fileNames: the library's file names and the source files', without their folders.
    public init(home: String, userNames: [String], wallpaperNames: [String], fileNames: [String]) {
        var kinds: [String: Placeholder] = [:]
        for (list, kind) in [(userNames, Placeholder.user), (wallpaperNames, .wallpaper), (fileNames, .file)] {
            for name in list.map(Self.trimmed) where !name.isEmpty {
                kinds[Self.folded(name)] = kinds[Self.folded(name)] ?? kind
            }
        }
        self.kinds = kinds
        // Longest first, so that "Evening Tide" is taken whole before "Tide" can be.
        let alternatives = kinds.keys.sorted { ($0.count, $0) > ($1.count, $1) }.map(NSRegularExpression.escapedPattern(for:))
        names = alternatives.isEmpty ? nil : Self.expression(
            #"(?<![\p{L}\p{N}])(?:"# + alternatives.joined(separator: "|") + #")(?![\p{L}\p{N}])"#, options: .caseInsensitive
        )

        let rest = #"[^\s"'()\[\]{},;]*"#
        let home = Self.trimmed(home).trimmingSuffix("/")
        var paths = [
            // `~` for the home folder, `~name` for someone's.
            #"(?<![\p{L}\p{N}])~"# + rest,
            // A path starts at a slash that does not follow a word, and is not the first of two, as in `file:///`.
            #"(?<![\p{L}\p{N}_.\-])/(?=[^\s/"'()\[\]{},;])"# + rest,
        ]
        if !home.isEmpty { paths.insert(NSRegularExpression.escapedPattern(for: home) + rest, at: 0) }
        places = Self.expression("(" + paths.joined(separator: "|") + #")|(<private>)"#, options: .caseInsensitive)
    }

    /// Every wallpaper's name in the library, and the names of its files.
    public init(home: String, userNames: [String], library: Library, sourceFileNames: [String]) {
        let files = library.wallpapers.flatMap { wallpaper in
            [wallpaper.optimisedCopy, wallpaper.poster, wallpaper.hoverPreview, wallpaper.scene?.project].compactMap { path in
                path?.relative.split(separator: "/").last.map(String.init)
            }
        }
        self.init(home: home, userNames: userNames, wallpaperNames: library.wallpapers.map(\.name), fileNames: files + sourceFileNames)
    }

    public func redact(_ line: String) -> String {
        let text = NSMutableString(string: line)
        if let names {
            for match in names.matches(in: line, range: NSRange(location: 0, length: text.length)).reversed() {
                let name = Self.folded(text.substring(with: match.range))
                text.replaceCharacters(in: match.range, with: String((kinds[name] ?? .user).marker))
            }
        }
        let named = text as String
        for match in places.matches(in: named, range: NSRange(location: 0, length: text.length)).reversed() {
            let kind: Placeholder = match.range(at: 1).location == NSNotFound ? .hidden : .path
            text.replaceCharacters(in: match.range, with: String(kind.marker))
        }
        var result = text as String
        for kind in Placeholder.allCases {
            result = result.replacingOccurrences(of: String(kind.marker), with: kind.words)
        }
        return result
    }

    // MARK: Helpers

    /// What stands in for what was taken out. While a line is being redacted
    /// each is a single character from the private use area, which no name's
    /// pattern can match, and becomes its words at the end.
    private enum Placeholder: CaseIterable {
        case path, user, wallpaper, file, hidden

        var marker: Character {
            switch self {
            case .path: "\u{E000}"
            case .user: "\u{E001}"
            case .wallpaper: "\u{E002}"
            case .file: "\u{E003}"
            case .hidden: "\u{E004}"
            }
        }

        var words: String {
            switch self {
            case .path: "<path>"
            case .user: "<user>"
            case .wallpaper: "<wallpaper>"
            case .file: "<file>"
            case .hidden: "<hidden>"
            }
        }
    }

    private static func trimmed(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
    }

    private static func expression(_ pattern: String, options: NSRegularExpression.Options) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern, options: options)
        } catch {
            // Every name is escaped, so only a mistake in the fixed parts gets here.
            preconditionFailure("redaction pattern does not compile: \(error)")
        }
    }
}

extension String {
    fileprivate func trimmingSuffix(_ suffix: String) -> String {
        var text = self
        while text.count > 1, text.hasSuffix(suffix) { text.removeLast(suffix.count) }
        return text
    }
}
