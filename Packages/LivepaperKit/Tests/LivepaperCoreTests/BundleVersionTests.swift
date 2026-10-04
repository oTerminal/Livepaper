import Foundation
import Testing
import LivepaperCore

/// A bundle's version and build, in the one form onboarding's record and the diagnostics both use.
struct BundleVersionTests {
    @Test func `a version is said with its build`() {
        #expect(BundleVersion(version: "0.1.0", build: "1").words == "0.1.0 (1)")
    }

    @Test func `a bundle that names neither has no version`() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "BundleVersionTests-\(UUID().uuidString).bundle")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(BundleVersion(bundle: try #require(Bundle(url: folder))) == nil)
    }
}
