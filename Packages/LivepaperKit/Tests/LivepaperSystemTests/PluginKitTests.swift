import Foundation
import LivepaperCore
import LivepaperSystem
import Testing

/// What `pluginkit -m -i` prints, and whether it lists the extension.
struct PluginKitTests {
    static let id = WallpaperExtensionIdentity.bundleIdentifier

    static let outputs: [Row<String, Bool>] = [
        Row("the development Mac's answer, 2026-09-24", "     \(id)(0.1.0)\n", true),
        Row("nothing registered prints nothing", "", false),
        Row(
            "the verbose form, a tab after the version",
            "     \(id)(0.1.0)\t2A7B880A-A1D4-438E-91FB-F3851BE1F46E\t2026-09-24 10:34:37 +0000\t/Applications/Livepaper.app\n"
                + " (1 plug-in)\n",
            true
        ),
        Row("chosen by the user", "+    \(id)(0.1.0)\n", true),
        Row("superseded by another copy, which is listed too", "=    \(id)(0.1.0)\n     \(id)(0.2.0)\n", true),
        Row("turned off by the user", "-    \(id)(0.1.0)\n", false),
        Row("another extension whose name starts the same", "     \(id)Preview(0.1.0)\n", false),
        Row("another extension altogether", "     com.apple.wallpaper.extension.aerials(1.0)\n", false),
    ]

    @Test(arguments: outputs)
    func `whether the output lists the extension`(row: Row<String, Bool>) {
        #expect(PluginKit.lists(Self.id, in: row.input) == row.expected)
    }

    @Test func `the real pluginkit lists no extension by a name nobody has`() async {
        #expect(await PluginKit().isListed("app.livepaper.tests.nobody-has-this") == false)
    }
}
