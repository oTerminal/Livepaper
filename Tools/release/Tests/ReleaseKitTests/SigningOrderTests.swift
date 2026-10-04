import ReleaseKit
import Testing

/// The order `sign.sh` signs a bundle in, from the bundle's file listing: the
/// deepest code first, the extension with its entitlements file, the app last, and
/// a Mach-O the rules do not place refused rather than left unsigned.
struct SigningOrderTests {
    static let sparkle = "Contents/Frameworks/Sparkle.framework"
    static let extensionPath = "Contents/Extensions/WallpaperExtension.appex"

    /// A Release build of Livepaper as it is: Sparkle 2.10.0 by Swift
    /// package, the three helpers, the `livepaper` tool and the extension, with
    /// resources that are not code between them.
    static let livepaper: [BundleFile] = [
        .resource("Contents/Info.plist"),
        .machO("Contents/MacOS/Livepaper"),
        .machO("Contents/MacOS/ffmpeg"),
        .machO("Contents/MacOS/glslang"),
        .machO("Contents/MacOS/spirv-cross"),
        .machO("Contents/Helpers/livepaper"),
        .resource("Contents/Resources/Samples/Tall Grass.mp4"),
        .resource("Contents/Resources/Credits.rtf"),
        .machO("\(sparkle)/Versions/B/Sparkle"),
        .machO("\(sparkle)/Versions/B/Autoupdate"),
        .resource("\(sparkle)/Versions/B/Resources/Info.plist"),
        .machO("\(sparkle)/Versions/B/Updater.app/Contents/MacOS/Updater"),
        .resource("\(sparkle)/Versions/B/Updater.app/Contents/Info.plist"),
        .machO("\(sparkle)/Versions/B/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"),
        .machO("\(sparkle)/Versions/B/XPCServices/Installer.xpc/Contents/MacOS/Installer"),
        .machO("\(extensionPath)/Contents/MacOS/WallpaperExtension"),
        .resource("\(extensionPath)/Contents/Info.plist"),
    ]

    static func order(_ files: [BundleFile]) throws -> [SigningStep] {
        try signingOrder(of: files, appName: "Livepaper", rules: .livepaper)
    }

    @Test func signsEveryPieceOfCodeOnceAndTheAppLast() throws {
        let steps = try Self.order(Self.livepaper)
        #expect(Set(steps.map(\.path)) == [
            "\(Self.sparkle)/Versions/B/XPCServices/Downloader.xpc",
            "\(Self.sparkle)/Versions/B/XPCServices/Installer.xpc",
            "\(Self.sparkle)/Versions/B/Updater.app",
            "\(Self.sparkle)/Versions/B/Autoupdate",
            Self.sparkle,
            "Contents/MacOS/ffmpeg",
            "Contents/MacOS/glslang",
            "Contents/MacOS/spirv-cross",
            "Contents/Helpers/livepaper",
            Self.extensionPath,
            "",
        ])
        #expect(steps.count == 11)
        #expect(steps.last == SigningStep(path: "", identifier: nil, entitlements: nil))
    }

    @Test func signsWhatIsInsideBeforeWhatHoldsIt() throws {
        let paths = try Self.order(Self.livepaper).map(\.path)
        for (index, inner) in paths.enumerated() {
            for outer in paths[..<index] where outer.isEmpty || inner.hasPrefix(outer + "/") {
                Issue.record("\(outer) is signed before \(inner), which holds it")
            }
        }
        #expect(paths.firstIndex(of: "\(Self.sparkle)/Versions/B/Updater.app")! < paths.firstIndex(of: Self.sparkle)!)
    }

    @Test func theExtensionIsSignedWithItsEntitlementsFile() throws {
        let steps = try Self.order(Self.livepaper)
        let appex = try #require(steps.first { $0.path == Self.extensionPath })
        #expect(appex.entitlements == "WallpaperExtension/WallpaperExtension.entitlements")
        #expect(steps.filter { $0.entitlements != nil }.map(\.path) == [Self.extensionPath])
    }

    @Test func aLooseExecutableIsNamedByTheRulesAndABundleByItsInfoPlist() throws {
        let steps = try Self.order(Self.livepaper)
        let identifiers = Dictionary(uniqueKeysWithValues: steps.map { ($0.path, $0.identifier) })
        #expect(identifiers["Contents/MacOS/ffmpeg"] == "app.livepaper.Livepaper.ffmpeg")
        #expect(identifiers["Contents/MacOS/glslang"] == "app.livepaper.Livepaper.glslang")
        #expect(identifiers["Contents/MacOS/spirv-cross"] == "app.livepaper.Livepaper.spirv-cross")
        #expect(identifiers["Contents/Helpers/livepaper"] == "app.livepaper.cli")
        #expect(identifiers["\(Self.sparkle)/Versions/B/Autoupdate"] == "org.sparkle-project.Sparkle.Autoupdate")
        #expect(identifiers[Self.extensionPath] == .some(nil))
        #expect(identifiers[Self.sparkle] == .some(nil))
    }

    @Test func theSameListingInAnotherOrderSignsInTheSameOrder() throws {
        #expect(try Self.order(Self.livepaper.reversed()) == Self.order(Self.livepaper))
    }

    @Test func aMachOTheRulesDoNotPlaceIsRefused() {
        let stray = Self.livepaper + [.machO("Contents/Resources/libstray.dylib")]
        #expect(throws: SigningOrderError.unplaced("Contents/Resources/libstray.dylib")) { try Self.order(stray) }
    }

    @Test func aSecondExecutableBesideTheAppsOwnIsRefused() {
        let stray = Self.livepaper + [.machO("Contents/MacOS/ffprobe")]
        #expect(throws: SigningOrderError.unplaced("Contents/MacOS/ffprobe")) { try Self.order(stray) }
    }

    @Test func aMachOInsideANestedBundleThatIsNotItsExecutableIsRefused() {
        let stray = Self.livepaper + [.machO("\(Self.extensionPath)/Contents/Resources/helper")]
        #expect(throws: SigningOrderError.unplaced("\(Self.extensionPath)/Contents/Resources/helper")) {
            try Self.order(stray)
        }
    }

    @Test func aBundleWithoutItsExecutableIsRefused() {
        let hollow = Self.livepaper.filter { !$0.path.hasSuffix("Updater.app/Contents/MacOS/Updater") }
        #expect(throws: SigningOrderError.noExecutable("\(Self.sparkle)/Versions/B/Updater.app")) { try Self.order(hollow) }
    }

    @Test func aMissingExtensionIsRefused() {
        let withoutExtension = Self.livepaper.filter { !$0.path.hasPrefix(Self.extensionPath) }
        #expect(throws: SigningOrderError.missingBundle(Self.extensionPath)) { try Self.order(withoutExtension) }
    }

    @Test func anAppWithoutItsOwnExecutableIsRefused() {
        let hollow = Self.livepaper.filter { $0.path != "Contents/MacOS/Livepaper" }
        #expect(throws: SigningOrderError.noExecutable("")) { try Self.order(hollow) }
    }

    @Test func theToolLineNamesEachStep() throws {
        let lines = try Self.order(Self.livepaper).map(\.line)
        #expect(lines.contains("Contents/MacOS/ffmpeg\tapp.livepaper.Livepaper.ffmpeg\t-"))
        #expect(lines.contains("\(Self.extensionPath)\t-\tWallpaperExtension/WallpaperExtension.entitlements"))
        #expect(lines.last == ".\t-\t-")
    }
}
