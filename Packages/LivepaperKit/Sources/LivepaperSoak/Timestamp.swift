import Foundation

/// The soak's times: `log show`'s `2026-09-28 09:59:29.496734+0100` and the
/// CSVs' `2026-09-28T10:00:00+0100`. Read by hand, so no calendar or time zone is consulted.
enum Timestamp {
    static func date(_ text: Substring) -> Date? {
        guard text.count >= 24 else { return nil }
        let separator = text.index(text.startIndex, offsetBy: 10)
        guard text[separator] == " " || text[separator] == "T" else { return nil }
        let date = text[..<separator].split(separator: "-", omittingEmptySubsequences: false).compactMap { Int($0) }
        let clock = text[text.index(after: separator)...]
        guard date.count == 3, let sign = clock.lastIndex(where: { $0 == "+" || $0 == "-" }) else { return nil }
        let parts = clock[..<sign].split(separator: ":", omittingEmptySubsequences: false)
        let offset = clock[clock.index(after: sign)...]
        guard parts.count == 3, offset.count == 4, offset.allSatisfy(\.isNumber),
              let hour = Int(parts[0]), let minute = Int(parts[1]), let second = Double(parts[2]),
              let offsetHours = Int(offset.prefix(2)), let offsetMinutes = Int(offset.suffix(2)) else { return nil }
        let days = daysSinceEpoch(year: date[0], month: date[1], day: date[2])
        let direction: Double = clock[sign] == "+" ? 1 : -1
        let local = Double(days * 86_400 + hour * 3_600 + minute * 60) + second
        return Date(timeIntervalSince1970: local - direction * Double(offsetHours * 3_600 + offsetMinutes * 60))
    }

    /// Days from 1970-01-01 to a date in the proleptic Gregorian calendar
    /// (Howard Hinnant's `days_from_civil`).
    private static func daysSinceEpoch(year: Int, month: Int, day: Int) -> Int {
        let year = month <= 2 ? year - 1 : year
        let era = (year >= 0 ? year : year - 399) / 400
        let yearOfEra = year - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146_097 + dayOfEra - 719_468
    }
}
