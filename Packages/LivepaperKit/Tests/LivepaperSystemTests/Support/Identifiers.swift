import Foundation
import LivepaperCore

extension DisplayIdentity {
    /// A readable, fixed display: display 1 is always the same display.
    static func numbered(_ number: Int) -> DisplayIdentity {
        let digits = String(number)
        let padded = String(repeating: "0", count: 12 - digits.count) + digits
        guard let uuid = UUID(uuidString: "DDDDDDDD-0000-0000-0000-\(padded)") else {
            preconditionFailure("not a UUID: \(number)")
        }
        return DisplayIdentity(uuid: uuid)
    }
}
