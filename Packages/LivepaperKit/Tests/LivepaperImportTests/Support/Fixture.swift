import Foundation
import Testing

/// The fixture corpus, made by `Fixtures/make-fixtures.sh` and checked in.
enum Fixture {
    static func url(_ name: String) throws -> URL {
        let file = name as NSString
        return try #require(
            Bundle.module.url(forResource: file.deletingPathExtension, withExtension: file.pathExtension, subdirectory: "Fixtures"),
            "no fixture named \(name)"
        )
    }
}
