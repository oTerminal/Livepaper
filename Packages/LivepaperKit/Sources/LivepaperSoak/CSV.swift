import Foundation

/// The soak's CSVs: plain comma-separated fields, no quoting (`soak.sh` and `energy.sh` write none).
enum CSV {
    /// Every row after `header` that `parse` reads, and how many it could not: a row that
    /// does not read is counted, never guessed at. Blank lines are skipped.
    static func read<Row>(_ text: String, header: String, parse: ([Substring]) -> Row?) -> ([Row], Int) {
        var rows: [Row] = []
        var unread = 0
        for line in text.split(whereSeparator: \.isNewline) where !line.trimmingCharacters(in: .whitespaces).isEmpty && line != header {
            if let row = parse(line.split(separator: ",", omittingEmptySubsequences: false)) {
                rows.append(row)
            } else {
                unread += 1
            }
        }
        return (rows, unread)
    }
}
