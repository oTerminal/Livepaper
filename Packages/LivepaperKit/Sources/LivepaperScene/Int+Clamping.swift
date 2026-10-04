import Foundation

extension Int {
    /// A float as a whole number, cut toward zero, where `Int(_:)` would trap:
    /// not a number is zero, and one past what an `Int` holds, infinity
    /// included, is held to the largest or the smallest. Every float read from
    /// a scene's files, or worked out from one, is made whole this way.
    init<Source: BinaryFloatingPoint>(clamping value: Source) {
        if value.isNaN {
            self = 0
        } else if value >= Source(Int.max) {
            self = .max
        } else if value <= Source(Int.min) {
            self = .min
        } else {
            self = Int(value)
        }
    }
}
