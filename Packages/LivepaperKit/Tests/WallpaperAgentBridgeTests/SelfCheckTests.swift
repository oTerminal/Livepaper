import Testing
@testable import WallpaperAgentBridge

struct SelfCheckTests {
    struct Verdict: Sendable, Equatable {
        var isUsable: Bool
        var line: String
    }

    static let compositing = "-[AVSampleBufferDisplayLayer _setDisallowsVideoLayerDisplayCompositing:]"

    static let rows: [Row<[BridgeRequirement], Verdict>] = [
        Row("nothing missing", [], Verdict(isUsable: true, line: "bridge self-check: all present")),
        Row(
            "the video compositing selector is not needed to show a wallpaper",
            [.videoCompositingSelector],
            Verdict(isUsable: true, line: "bridge self-check: usable, missing: \(compositing)")
        ),
        Row(
            "the snapshot layout and the classes of unused calls are not needed either",
            [.payloadClass("AuditTokenXPC"), .payloadClass("WallpaperSnapshotXPC"), .snapshotReplyLayout],
            Verdict(
                isUsable: true,
                line: "bridge self-check: usable, missing: AuditTokenXPC, WallpaperSnapshotXPC, WallpaperSnapshotXPC.rawValue"
            )
        ),
        Row(
            "a context that cannot be invalidated is kept until the process ends",
            [.remoteContextInvalidate],
            Verdict(isUsable: true, line: "bridge self-check: usable, missing: -[CAContext invalidate]")
        ),
        Row(
            "without the framework nothing can be shown",
            [.framework, .videoCompositingSelector],
            Verdict(isUsable: false, line: "bridge self-check: failed, missing: WallpaperExtensionKit, \(compositing)")
        ),
        Row(
            "without the acquire request's class nothing can be shown",
            [.payloadClass("WallpaperCreationRequestXPC")],
            Verdict(isUsable: false, line: "bridge self-check: failed, missing: WallpaperCreationRequestXPC")
        ),
        Row(
            "without the surface identifier's class nothing can be shown",
            [.payloadClass("WallpaperIDXPC")],
            Verdict(isUsable: false, line: "bridge self-check: failed, missing: WallpaperIDXPC")
        ),
        Row(
            "without the acquire reply's layout nothing can be shown",
            [.remoteContextReplyLayout],
            Verdict(isUsable: false, line: "bridge self-check: failed, missing: WallpaperRemoteContextXPC.box")
        ),
        Row(
            "without remote contexts nothing can be shown",
            [.remoteContextFactory, .remoteContextAccessors],
            Verdict(
                isUsable: false,
                line: "bridge self-check: failed, missing: +[CAContext remoteContextWithOptions:], "
                    + "-[CAContext contextId layer setLayer:]"
            )
        ),
    ]

    @Test(arguments: rows)
    func `decides from what is missing whether wallpapers can be shown, in one line`(row: Row<[BridgeRequirement], Verdict>) {
        let check = BridgeSelfCheck(missing: row.input)

        #expect(Verdict(isUsable: check.isUsable, line: check.logLine) == row.expected)
    }

    @Test func `checks the fifteen payload classes`() {
        #expect(WallpaperAgentBridge.payloadClassNames.count == 15)
        #expect(Set(WallpaperAgentBridge.payloadClassNames).count == 15)
    }
}
