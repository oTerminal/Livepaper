import LivepaperCore
import Testing

/// What the first thing a launch does says about where Livepaper runs:
/// carry on, ask for the drag to Applications, or offer to move it there.
struct InstallDecisionTests {
    static let home = "/Users/someone"
    static let gatekeepers = "/private/var/folders/xy/abc/T/AppTranslocation/0F1E/d/Livepaper.app"

    /// A copy SecTranslocate said was not translocated, on a writable volume.
    static func at(_ path: String) -> InstallLocation {
        InstallLocation(bundlePath: path, isTranslocated: false, isVolumeWritable: true)
    }

    static let places: [Row<InstallLocation, InstallDecision>] = [
        Row("in /Applications: carries on", at("/Applications/Livepaper.app"), .proceed),
        Row("in ~/Applications: carries on", at("/Users/someone/Applications/Livepaper.app"), .proceed),
        Row("in a folder inside /Applications: carries on", at("/Applications/Utilities/Livepaper.app"), .proceed),
        Row("in a folder inside ~/Applications: carries on", at("/Users/someone/Applications/Wallpapers/Livepaper.app"), .proceed),
        Row("given with a trailing slash: still in /Applications", at("/Applications/Livepaper.app/"), .proceed),
        Row("given with doubled slashes: still in /Applications", at("//Applications//Livepaper.app"), .proceed),
        Row("/Applications in another case, as APFS reads it: carries on", at("/applications/Livepaper.app"), .proceed),
        Row("in Downloads: offers the move", at("/Users/someone/Downloads/Livepaper.app"), .offerMove),
        Row("on the Desktop: offers the move", at("/Users/someone/Desktop/Livepaper.app"), .offerMove),
        Row("in a folder that only starts with Applications: offers the move", at("/Applications Old/Livepaper.app"), .offerMove),
        Row("in /ApplicationsX: offers the move", at("/ApplicationsX/Livepaper.app"), .offerMove),
        Row("in ~/ApplicationsX: offers the move", at("/Users/someone/ApplicationsX/Livepaper.app"), .offerMove),
        Row("in another user's Applications: offers the move", at("/Users/other/Applications/Livepaper.app"), .offerMove),
        Row("in Applications under another folder: offers the move", at("/Users/someone/Downloads/Applications/Livepaper.app"), .offerMove),
        Row(
            "a path that climbs out of /Applications: offers the move",
            at("/Applications/../Users/someone/Downloads/Livepaper.app"), .offerMove
        ),
        Row(
            "translocated, as SecTranslocate says: asks for the drag",
            InstallLocation(bundlePath: gatekeepers, isTranslocated: true, isVolumeWritable: false),
            .askForDrag
        ),
        Row(
            "SecTranslocate not asked, and the path is Gatekeeper's: asks for the drag",
            InstallLocation(bundlePath: gatekeepers, isTranslocated: nil, isVolumeWritable: false),
            .askForDrag
        ),
        Row(
            "SecTranslocate not asked, the path is Gatekeeper's, the volume said writable: still asks for the drag",
            InstallLocation(bundlePath: gatekeepers, isTranslocated: nil, isVolumeWritable: true),
            .askForDrag
        ),
        Row(
            "SecTranslocate not asked, and an ordinary path: the path decides",
            InstallLocation(bundlePath: "/Users/someone/Downloads/Livepaper.app", isTranslocated: nil, isVolumeWritable: true),
            .offerMove
        ),
        Row(
            "SecTranslocate said no, in a folder merely named like Gatekeeper's: its answer stands",
            at("/Users/someone/AppTranslocation/Livepaper.app"), .offerMove
        ),
        Row(
            "on the mounted disk image, read-only: asks for the drag",
            InstallLocation(bundlePath: "/Volumes/Livepaper/Livepaper.app", isTranslocated: false, isVolumeWritable: false),
            .askForDrag
        ),
        Row(
            "on a read-only volume, though in /Applications: carries on, since there is nowhere better",
            InstallLocation(bundlePath: "/Applications/Livepaper.app", isTranslocated: false, isVolumeWritable: false),
            .proceed
        ),
    ]

    @Test(arguments: places)
    func `decides from where Livepaper runs`(row: Row<InstallLocation, InstallDecision>) {
        #expect(installDecision(row.input, homeDirectory: Self.home, declinedPaths: []) == row.expected)
    }

    @Test func `a home folder given with a trailing slash still finds ~/Applications`() {
        let decision = installDecision(
            Self.at("/Users/someone/Applications/Livepaper.app"), homeDirectory: "/Users/someone/", declinedPaths: []
        )

        #expect(decision == .proceed)
    }

    // MARK: Not Now

    static let declined: Set<String> = ["/Users/someone/Downloads/Livepaper.app"]

    static let notNow: [Row<InstallLocation, InstallDecision>] = [
        Row("the path Not Now was answered for: carries on", at("/Users/someone/Downloads/Livepaper.app"), .proceed),
        Row("that path with a trailing slash: carries on", at("/Users/someone/Downloads/Livepaper.app/"), .proceed),
        Row("another path: offers the move again", at("/Users/someone/Desktop/Livepaper.app"), .offerMove),
        Row("another copy in the same folder: offers the move", at("/Users/someone/Downloads/Livepaper 2.app"), .offerMove),
        Row(
            "that path, now on a read-only volume: asks for the drag, which Not Now never answered",
            InstallLocation(bundlePath: "/Users/someone/Downloads/Livepaper.app", isTranslocated: false, isVolumeWritable: false),
            .askForDrag
        ),
        Row(
            "that path, translocated: asks for the drag",
            InstallLocation(bundlePath: "/Users/someone/Downloads/Livepaper.app", isTranslocated: true, isVolumeWritable: true),
            .askForDrag
        ),
    ]

    @Test(arguments: notNow)
    func `answering Not Now binds to that path only`(row: Row<InstallLocation, InstallDecision>) {
        #expect(installDecision(row.input, homeDirectory: Self.home, declinedPaths: Self.declined) == row.expected)
    }

    @Test func `a path declined with a trailing slash binds to the same path`() {
        let decision = installDecision(
            Self.at("/Users/someone/Downloads/Livepaper.app"),
            homeDirectory: Self.home,
            declinedPaths: ["/Users/someone/Downloads/Livepaper.app/"]
        )

        #expect(decision == .proceed)
    }
}
