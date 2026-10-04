import Foundation
import Testing
import LivepaperCore

/// A log line never holds a path, a user name or a source file's name: an error
/// goes into one by its kind.
struct LogWordsTests {
    static let home = "/Users/sam"

    @Test func `a system error is its domain and code, and the POSIX error under it, never the path it names`() {
        let error = NSError(domain: NSCocoaErrorDomain, code: 513, userInfo: [
            NSFilePathErrorKey: "\(Self.home)/Desktop/Livepaper Diagnostics.txt",
            NSUnderlyingErrorKey: NSError(domain: NSPOSIXErrorDomain, code: 13),
        ])

        #expect(LogWords.kind(of: error) == "NSCocoaErrorDomain 513, POSIX error 13")
    }

    @Test func `a Foundation error thrown by a write is logged by kind`() {
        let temporary = FileManager.default.temporaryDirectory
        let missing = temporary.appending(path: "LogWordsTests-\(UUID().uuidString)/report.txt", directoryHint: .notDirectory)

        do {
            try Data().write(to: missing)
            Issue.record("the write should have failed: its folder is not there")
        } catch {
            let kind = LogWords.kind(of: error)
            #expect(kind.hasPrefix("NSCocoaErrorDomain "))
            #expect(!kind.contains(temporary.path))
            #expect(!kind.contains("report"))
        }
    }

    struct Named: KindNamingError {
        var kind: String { "another copy of Livepaper answers there" }
    }

    @Test func `an error that names its kind is logged by it`() {
        #expect(LogWords.kind(of: Named()) == "another copy of Livepaper answers there")
    }
}
