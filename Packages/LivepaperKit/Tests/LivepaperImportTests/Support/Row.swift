import Foundation
import Testing

/// One row of a table test. The name is what the test report shows, so it says
/// what the row proves.
struct Row<Input: Sendable, Expected: Sendable>: Sendable, CustomTestStringConvertible {
    let name: String
    let input: Input
    let expected: Expected

    init(_ name: String, _ input: Input, _ expected: Expected) {
        self.name = name
        self.input = input
        self.expected = expected
    }

    var testDescription: String { name }
}

/// Fixed points in time. No test reads the clock.
enum Moment {
    static let launch = Date(timeIntervalSince1970: 1_790_000_000)

    static func after(_ seconds: TimeInterval) -> Date {
        launch.addingTimeInterval(seconds)
    }
}
