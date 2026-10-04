/// `CHANGELOG.md`: a `## X.Y.Z` section per release, which is that release's notes
/// in the appcast and its body on GitHub. Text after the version on the heading line
/// (a date, say) is allowed.
public enum Changelog {
    /// The section's text, without its heading and trimmed of blank lines.
    public static func section(for version: String, in changelog: String) throws(ChangelogError) -> String {
        let lines = changelog.split(separator: "\n", omittingEmptySubsequences: false)
        let starts = lines.indices.filter { isHeading(lines[$0], of: version) }
        guard let start = starts.first else { throw .missing(version) }
        guard starts.count == 1 else { throw .doubled(version) }
        let body = lines[(start + 1)...].prefix { !$0.hasPrefix("## ") && !$0.hasPrefix("# ") }
        let text = body.joined(separator: "\n").trimmingBlankLines()
        guard !text.isEmpty else { throw .empty(version) }
        return text
    }

    private static func isHeading(_ line: Substring, of version: String) -> Bool {
        guard line.hasPrefix("## ") else { return false }
        let rest = line.dropFirst(3)
        guard rest.hasPrefix(version) else { return false }
        let after = rest.dropFirst(version.count)
        return after.isEmpty || after.first == " "
    }
}

public enum ChangelogError: Error, Hashable, CustomStringConvertible {
    case missing(String)
    case empty(String)
    case doubled(String)

    public var description: String {
        switch self {
        case .missing(let version): "CHANGELOG.md has no ## \(version) section: write the release's notes first"
        case .empty(let version): "CHANGELOG.md's ## \(version) section is empty"
        case .doubled(let version): "CHANGELOG.md has two ## \(version) sections"
        }
    }
}

extension String {
    /// Without the blank lines at either end; lines keep their own indentation.
    func trimmingBlankLines() -> String {
        let lines = split(separator: "\n", omittingEmptySubsequences: false)
        let isBlank: (Substring) -> Bool = { $0.allSatisfy(\.isWhitespace) }
        guard let first = lines.firstIndex(where: { !isBlank($0) }), let last = lines.lastIndex(where: { !isBlank($0) }) else {
            return ""
        }
        return lines[first...last].joined(separator: "\n")
    }
}
