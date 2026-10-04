import Testing
import DesignSystem

/// A status line's words are a sentence without its full stop, as the app's own
/// lines are ("Livepaper is not your wallpaper", "Importing 2 of 5").
struct StatusLineWordsTests {
    @Test func `the service not responding is said without a full stop`() {
        #expect(StatusLineStatus.serviceNotResponding.words == "Wallpaper service not responding")
    }

    @Test(arguments: [
        (status: StatusLineStatus.idle("Live on 1 display"), words: "Live on 1 display"),
        (status: StatusLineStatus.working("Importing 2 of 5"), words: "Importing 2 of 5"),
    ])
    func `the caller's words are said as given`(status: StatusLineStatus, words: String) {
        #expect(status.words == words)
    }
}
