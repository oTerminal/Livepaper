import Foundation

/// A bundle's version and build, as its Info.plist gives them: what onboarding's
/// record keeps and what the diagnostics report says of the app and the extension.
public struct BundleVersion: Equatable, Sendable {
    public var version: String
    public var build: String

    public init(version: String, build: String) {
        self.version = version
        self.build = build
    }

    /// Nil when the bundle names neither.
    public init?(bundle: Bundle) {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        guard version != nil || build != nil else { return nil }
        self.init(version: version ?? "unknown", build: build ?? "unknown")
    }

    /// This process's bundle, "unknown" for what its Info.plist does not name.
    public static var main: BundleVersion {
        BundleVersion(bundle: .main) ?? BundleVersion(version: "unknown", build: "unknown")
    }

    /// "0.1.0 (1)": the marketing version and the build.
    public var words: String { "\(version) (\(build))" }
}
