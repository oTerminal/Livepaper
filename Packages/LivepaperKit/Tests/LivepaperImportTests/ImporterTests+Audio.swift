import Foundation
import Testing
import LivepaperCore
import LivepaperImport

// The copy's audio, which every import encodes again, whatever it does with the video.
extension ImporterTests {
    @Test func `the copy's audio comes out at no higher a rate than it went in`() async throws {
        let source = try Fixture.url("noisy-audio.mp4")

        let outcome = try await bench.importer().run(ImportCandidate(source: source, name: "Noisy"))

        guard case .imported(let wallpaper, _) = outcome else {
            Issue.record("not imported: \(outcome)")
            return
        }
        let copy = try await audioBitRate(of: bench.location.url(for: wallpaper.optimisedCopy))
        let original = try await audioBitRate(of: source)
        #expect(copy <= original, "the copy's audio runs at \(Int(copy)) bit/s, the source's at \(Int(original))")
    }
}
