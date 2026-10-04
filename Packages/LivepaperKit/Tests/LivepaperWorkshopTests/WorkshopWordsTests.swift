import Foundation
import Testing
import LivepaperWorkshop

/// Every word the Workshop's screens say when something did not work, pinned.
struct WorkshopWordsTests {
    typealias Words = WorkshopFailureWords

    static let failures: [Row<WorkshopError, Words>] = [
        Row("a password Steam refused", .wrongPassword, .signIn("Steam did not accept that account name and password")),
        Row(
            "a code Steam refused",
            .wrongCode,
            .signIn("Steam did not accept that code. Codes last a short while, so use the newest one")
        ),
        Row("too many tries", .rateLimited, .retryable("Steam has had too many sign-ins from this Mac. Wait a while, then try again")),
        Row("Steam not answering", .timedOut, .retryable("Steam did not answer in time")),
        Row("no network", .noConnection, .retryable("Steam could not be reached. Check the Mac is online")),
        Row("no saved login", .signInNeeded, .signIn("Livepaper is not signed in to Steam")),
        Row(
            "an account that does not own Wallpaper Engine",
            .notOwned,
            .final(
                "Steam would not give it to this account. "
                    + "Wallpaper Engine’s Workshop items download only for an account that owns Wallpaper Engine"
            )
        ),
        Row("an item Steam does not have", .itemNotFound, .final("Steam has no such Workshop item. It may have been taken down")),
        Row(
            "a sign-out that did not take",
            .stillSignedIn,
            .retryable("Steam still signed in without a password, so the saved login was not taken back")
        ),
        Row("anything else Steam says, in its words", .steamSaid("Account Disabled"), .retryable("Steam answered “Account Disabled”")),
        Row(
            "a name no Steam account could have",
            .notAnAccountName,
            .signIn("A Steam account name is made of letters, digits and underscores")
        ),
        Row("another game's item", .notWallpaperEngine, .final("It is a Workshop item for another game, not for Wallpaper Engine")),
        Row(
            "no Rosetta",
            .rosettaMissing,
            .retryable(
                "Steam’s download tool is made for Intel Macs and needs Rosetta, which is not installed. "
                    + "Install it with “softwareupdate --install-rosetta” in Terminal, then try again"
            )
        ),
        Row(
            "a tool without Valve's signature",
            .toolUntrusted,
            .final("Steam’s download tool did not carry Valve’s signature, so Livepaper did not run it")
        ),
        Row("the tool could not be fetched", .toolNotDownloaded, .retryable("Steam’s download tool could not be fetched from Valve")),
        Row("the tool would not start", .toolNotStarted, .retryable("Steam’s download tool could not be started")),
        Row("the tool stopped", .toolStopped(status: 1), .retryable("Steam’s download tool stopped before it finished")),
        Row("the tool said nothing", .noAnswer, .retryable("Steam’s download tool ended without saying whether it worked")),
        Row(
            "a folder with nothing to import in it",
            .nothingToImport,
            .final("Steam downloaded it, but its folder holds nothing Livepaper can import")
        ),
    ]

    @Test(arguments: failures)
    func `says what went wrong`(row: Row<WorkshopError, Words>) {
        #expect(workshopFailureWords(row.input) == row.expected)
    }

    @Test func `no reason ends in a full stop, since a row or toast adds its own`() {
        for row in Self.failures {
            #expect(!workshopFailureWords(row.input).reason.hasSuffix("."))
        }
    }
}
