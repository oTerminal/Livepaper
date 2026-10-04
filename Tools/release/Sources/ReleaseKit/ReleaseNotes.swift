import Foundation

/// A changelog section as the HTML Sparkle's update window shows: paragraphs,
/// `-` lists, `###` headings, and inline `code`, **strong** and [links](url).
/// Everything else is text, escaped.
public enum ReleaseNotes {
    public static func html(markdown: String) -> String {
        var blocks: [String] = []
        var paragraph: [String] = []
        var items: [String] = []

        func flush() {
            if !paragraph.isEmpty { blocks.append("<p>\(paragraph.joined(separator: "\n"))</p>") }
            if !items.isEmpty { blocks.append((["<ul>"] + items.map { "<li>\($0)</li>" } + ["</ul>"]).joined(separator: "\n")) }
            paragraph = []
            items = []
        }

        for raw in markdown.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.trimmingWhitespace()
            if line.isEmpty {
                flush()
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                if !paragraph.isEmpty { flush() }
                items.append(inline(String(line.dropFirst(2))))
            } else if let heading = line.firstIndex(where: { $0 != "#" }), line.hasPrefix("#"), line[heading] == " " {
                flush()
                let level = min(line.distance(from: line.startIndex, to: heading), 6)
                blocks.append("<h\(level)>\(inline(String(line[heading...].dropFirst())))</h\(level)>")
            } else if !items.isEmpty {
                // A wrapped list item goes on with its item.
                items[items.count - 1] += " " + inline(line)
            } else {
                paragraph.append(inline(line))
            }
        }
        flush()
        return blocks.joined(separator: "\n")
    }

    /// Escapes the text, then turns `code`, **strong** and [text](url) into tags.
    private static func inline(_ text: String) -> String {
        var html = ""
        var rest = Substring(text)
        while let first = rest.first {
            if first == "`", let end = rest.dropFirst().firstIndex(of: "`") {
                html += "<code>\(escape(rest[rest.index(after: rest.startIndex)..<end]))</code>"
                rest = rest[rest.index(after: end)...]
            } else if rest.hasPrefix("**"), let end = rest.dropFirst(2).range(of: "**") {
                html += "<strong>\(inline(String(rest[rest.index(rest.startIndex, offsetBy: 2)..<end.lowerBound])))</strong>"
                rest = rest[end.upperBound...]
            } else if first == "[", let link = rest.prefixMatch(of: #/\[([^\]]+)\]\(([^)\s]+)\)/#) {
                html += #"<a href="\#(escape(link.2))">\#(inline(String(link.1)))</a>"#
                rest = rest[link.range.upperBound...]
            } else {
                html += escape(String(first))
                rest = rest.dropFirst()
            }
        }
        return html
    }

    static func escape(_ text: some StringProtocol) -> String {
        var escaped = ""
        for character in text {
            switch character {
            case "&": escaped += "&amp;"
            case "<": escaped += "&lt;"
            case ">": escaped += "&gt;"
            case "\"": escaped += "&quot;"
            default: escaped.append(character)
            }
        }
        return escaped
    }
}

extension Substring {
    func trimmingWhitespace() -> String {
        String(drop(while: \.isWhitespace).reversed().drop(while: \.isWhitespace).reversed())
    }
}
