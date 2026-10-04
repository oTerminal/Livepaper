import Foundation
import Testing
import LivepaperCore

struct EnclosingAppTests {
    @Test func `the tool inside an app opens that app`() {
        let tool = URL(filePath: "/Applications/Livepaper.app/Contents/Helpers/livepaper")
        #expect(enclosingApp(ofTool: tool)?.path == "/Applications/Livepaper.app")
    }

    @Test func `a copy of the app anywhere is the one its tool opens`() {
        let tool = URL(filePath: "/Users/someone/Builds/Frozen/Livepaper.app/Contents/Helpers/livepaper")
        #expect(enclosingApp(ofTool: tool)?.path == "/Users/someone/Builds/Frozen/Livepaper.app")
    }

    @Test(arguments: [
        "/usr/local/bin/livepaper",
        "/Applications/Livepaper.app/Contents/MacOS/livepaper",
        "/Applications/Livepaper/Contents/Helpers/livepaper",
        "/Contents/Helpers/livepaper",
        "livepaper",
    ])
    func `a tool that is not in an app's Helpers has no app of its own`(path: String) {
        #expect(enclosingApp(ofTool: URL(filePath: path)) == nil)
    }
}
