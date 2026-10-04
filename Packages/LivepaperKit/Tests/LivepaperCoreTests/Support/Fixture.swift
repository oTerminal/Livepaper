import Foundation
import Testing

/// Files checked in beside the tests. A fixture written by schema version N
/// stays as it is for good: it is the proof that version N still loads.
enum Fixture {
    static func data(_ name: String) throws -> Data {
        let url = try #require(
            Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
            "no fixture named \(name).json"
        )
        return try Data(contentsOf: url)
    }
}
