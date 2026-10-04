import LivepaperCore
import Testing

/// What the hotkey recorder says already uses a combination: "⌃⌥N is already used by <owner>".
struct HotkeyWordsTests {
    static let owners: [Row<HotkeyAvailability, String?>] = [
        Row("a free combination has no owner", .free, nil),
        Row("another action's names the action", .usedBy(.nextWallpaper), "Next Wallpaper"),
        Row("one macOS or another app keeps", .takenElsewhere, "macOS or another app"),
    ]

    @Test(arguments: owners)
    func `names what already uses a combination`(row: Row<HotkeyAvailability, String?>) {
        #expect(row.input.owner == row.expected)
    }
}
