import Foundation

/// A soak's `log show` export, read line by line: what each line of the
/// categories the soak reads is, in time order. `soak.sh` appends one export an
/// hour, so a line two exports share is read once.
public struct SoakLog: Sendable {
    public struct Entry: Equatable, Sendable {
        public var line: LogLine
        public var event: SoakEvent
    }

    /// Every line of the categories the soak reads: events, known lines and unparsed ones, for excerpts.
    public private(set) var lines: [LogLine] = []
    public private(set) var entries: [Entry] = []
    public private(set) var unparsed: [LogLine] = []
    /// Lines of other subsystems and categories.
    public private(set) var ignoredCount = 0

    public init(text: String) {
        var records: [LogLine] = []
        var isInOtherRecord = false
        var seen: Set<String> = []
        var headless = 0
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = String(raw)
            if let line = LogLine(text) {
                isInOtherRecord = !seen.insert(text).inserted
                if !isInOtherRecord { records.append(line) }
            } else if Self.startsWithDate(text) || Self.isFrame(text) {
                // A line with no subsystem, or `log show`'s header and summary.
                if Self.startsWithDate(text) { headless += 1 }
                isInOtherRecord = true
            } else if !isInOtherRecord, !records.isEmpty {
                records[records.count - 1].message += "\n" + text
                records[records.count - 1].text += "\n" + text
            }
        }
        self.init(lines: records)
        ignoredCount += headless
    }

    public init(lines records: [LogLine]) {
        // Exports are in time order; a stable sort keeps a clock step from reordering the rest.
        for line in records.enumerated().sorted(by: { ($0.element.time, $0.offset) < ($1.element.time, $1.offset) }).map(\.element) {
            switch Reading(line) {
            case .event(let event):
                lines.append(line)
                entries.append(Entry(line: line, event: event))
            case .known:
                lines.append(line)
            case .unparsed:
                lines.append(line)
                unparsed.append(line)
            case .ignored:
                ignoredCount += 1
            }
        }
    }

    private static func startsWithDate(_ text: String) -> Bool {
        let head = Array(text.utf8.prefix(11))
        guard head.count == 11 else { return false }
        let digits = [0, 1, 2, 3, 5, 6, 8, 9].allSatisfy { (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(head[$0]) }
        return digits && head[4] == UInt8(ascii: "-") && head[7] == UInt8(ascii: "-") && head[10] == UInt8(ascii: " ")
    }

    /// `log show`'s own lines: the column header and the summary it ends with.
    private static func isFrame(_ text: String) -> Bool {
        ["Timestamp ", "Log ", "Activity ", "Boundary ", "Signpost ", "Timesync ", "Statedump ", "Loss ", "---"]
            .contains(where: text.hasPrefix) || text.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
