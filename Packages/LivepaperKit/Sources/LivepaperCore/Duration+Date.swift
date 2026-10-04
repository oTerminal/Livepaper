import Foundation

// Durations on the wall clock, in one place: the host's ladder, Selection's
// wait and the status line's Restart all count in `Duration` from a `Date`.

extension Duration {
    /// The duration in seconds, as `Date` counts them.
    public var timeInterval: TimeInterval {
        Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}

extension Date {
    /// The date `duration` later.
    public static func + (date: Date, duration: Duration) -> Date {
        date.addingTimeInterval(duration.timeInterval)
    }

    func elapsed(since earlier: Date) -> Duration {
        .seconds(timeIntervalSince(earlier))
    }
}
