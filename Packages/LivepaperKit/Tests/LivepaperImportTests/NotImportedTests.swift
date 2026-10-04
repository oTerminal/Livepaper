import Foundation
import LivepaperImport
import Testing

/// Why a source onboarding's first card was handed gave no wallpaper: skipped
/// by discovery, not searched, failed or cancelled, in the words the toasts use.
struct NotImportedTests {
    @Test func `a skipped source, one that could not be searched, and one cancelled say why`() {
        let skipped = SkippedSource(url: URL(filePath: "/Users/tester/Downloads/431960"), reason: .wallpaperEngine(.runsCode("web")))

        #expect(NotImported.skipped(skipped) == NotImported(
            name: "431960",
            reason: "It is a web page for Wallpaper Engine, which runs code of its own; only video and scene items can be imported"
        ))
        #expect(
            NotImported(name: "Gone", error: DiscoverError.notFound(URL(filePath: "/Gone")))
                == NotImported(name: "Gone", reason: "It could not be found")
        )
        #expect(NotImported.cancelled(name: "Harbour 1") == NotImported(name: "Harbour 1", reason: "Its import was cancelled"))
    }

    @Test func `it is said in one sentence, as the card shows it`() {
        let broken = NotImported(name: "Broken", reason: "It has no picture to play")

        #expect(broken.line == "“Broken” was not imported. It has no picture to play.")
    }
}
