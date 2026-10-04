import Foundation

/// One line of `log show`'s default style, the one `Tools/soak/soak.sh` exports:
///
///     2026-09-28 09:59:29.496734+0100 0x1990     Default     0x0      711    0    WallpaperExtension: (sender) [subsystem:category] message
///
/// That style carries each line's offset from UTC, which the compact one does not.
public struct LogLine: Equatable, Sendable {
    public var time: Date
    public var process: String
    public var pid: Int
    public var subsystem: String
    public var category: String
    public var message: String
    /// The line as `log show` printed it, for the report's excerpts.
    public var text: String

    public init(time: Date, process: String, pid: Int, subsystem: String, category: String, message: String, text: String) {
        self.time = time
        self.process = process
        self.pid = pid
        self.subsystem = subsystem
        self.category = category
        self.message = message
        self.text = text
    }

    /// Nil for anything that is not a line with a subsystem: the header, the
    /// summary at the end, a message's continuation.
    public init?(_ text: String) {
        // `2026-09-28 09:59:29.496734+0100`: the date, a space, the time and its offset.
        let date = text.prefix(while: { $0 != " " })
        let clock = text.dropFirst(date.count + 1).prefix(while: { $0 != " " })
        guard let time = Timestamp.date(text.prefix(date.count + 1 + clock.count)) else { return nil }
        var rest = text.dropFirst(date.count + 1 + clock.count)
        // Thread, type, activity, PID and TTL, separated by runs of spaces.
        var columns: [Substring] = []
        for _ in 0..<5 {
            rest = rest.drop(while: { $0 == " " })
            let column = rest.prefix(while: { $0 != " " })
            guard !column.isEmpty else { return nil }
            columns.append(column)
            rest = rest.dropFirst(column.count)
        }
        rest = rest.drop(while: { $0 == " " })
        guard let pid = Int(columns[3]),
              let colon = rest.range(of: ": ") else { return nil }
        let process = rest[..<colon.lowerBound]
        rest = rest[colon.upperBound...]
        // The sender, `(WallpaperExtension.debug.dylib)`, when there is one.
        if rest.first == "(", let close = rest.range(of: ") ") {
            rest = rest[close.upperBound...]
        }
        guard rest.first == "[",
              let close = rest.range(of: "] ") ?? (rest.last == "]" ? rest.range(of: "]", options: .backwards) : nil),
              let separator = rest[..<close.lowerBound].firstIndex(of: ":") else { return nil }
        self.init(
            time: time,
            process: String(process),
            pid: pid,
            subsystem: String(rest[rest.index(after: rest.startIndex)..<separator]),
            category: String(rest[rest.index(after: separator)..<close.lowerBound]),
            message: String(rest[close.upperBound...]),
            text: text
        )
    }
}
