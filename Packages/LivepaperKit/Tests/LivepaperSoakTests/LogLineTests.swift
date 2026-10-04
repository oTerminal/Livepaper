import Foundation
import LivepaperSoak
import Testing

/// `log show`'s default style, which carries each line's offset from UTC, taken apart.
struct LogLineTests {
    @Test
    func `reads a real line's time, process, subsystem, category and message`() throws {
        let text = "2026-09-28 09:59:29.496734+0100 0x1990     Default     0x0                  711    0    "
            + "WallpaperExtension: (WallpaperExtension.debug.dylib) [app.livepaper.extension:supervisor] "
            + "decision display=37D8832A-2D66-02CA-B9F7-8F30A301B230 decision=still generation=2293"

        let line = try #require(LogLine(text))

        // 08:59:29.496734 UTC.
        #expect(abs(line.time.timeIntervalSince1970 - 1_790_585_969.496734) < 0.000_01)
        #expect(line.process == "WallpaperExtension")
        #expect(line.pid == 711)
        #expect(line.subsystem == "app.livepaper.extension")
        #expect(line.category == "supervisor")
        #expect(line.message == "decision display=37D8832A-2D66-02CA-B9F7-8F30A301B230 decision=still generation=2293")
        #expect(line.text == text)
    }
}
