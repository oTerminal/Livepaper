/// A release's version, read from `project.yml` and nowhere else: `MARKETING_VERSION`,
/// `X.Y.Z`, which the tag names, and `CURRENT_PROJECT_VERSION`, the build, a whole
/// number that Sparkle orders updates by (`CFBundleVersion`).
public struct ReleaseVersion: Hashable, Sendable {
    public var marketing: String
    public var build: Int

    public init(marketing: String, build: Int) {
        self.marketing = marketing
        self.build = build
    }

    /// Reads both from `project.yml`, where each is set once, in `settings.base`.
    public init(projectYML: String) throws(VersionError) {
        let marketing = try Self.setting("MARKETING_VERSION", in: projectYML)
        let build = try Self.setting("CURRENT_PROJECT_VERSION", in: projectYML)
        guard Self.isVersion(marketing) else { throw .badMarketing(marketing) }
        guard build.allSatisfy(\.isASCII), let number = Int(build), number > 0, String(number) == build else {
            throw .badBuild(build)
        }
        self.init(marketing: marketing, build: number)
    }

    /// The tag that starts this release: `v` plus the marketing version.
    public var tag: String { "v\(marketing)" }

    /// Passes when the tag, or a `refs/tags/` ref, is this release's. A tag that is
    /// not `v` plus `X.Y.Z` starts nothing, whatever the version.
    public func check(tag ref: String) throws(VersionError) {
        let tag = ref.hasPrefix("refs/tags/") ? String(ref.dropFirst("refs/tags/".count)) : ref
        guard tag.hasPrefix("v"), Self.isVersion(String(tag.dropFirst())) else { throw .notAReleaseTag(tag) }
        guard tag == self.tag else { throw .tagMismatch(tag: tag, version: marketing) }
    }

    /// Passes when this build is above the last one the feed holds, or the feed is empty.
    public func check(after last: Int?) throws(VersionError) {
        if let last, build <= last { throw .buildNotAbove(build: build, last: last) }
    }

    /// `X.Y.Z`: three whole numbers without leading zeros.
    static func isVersion(_ text: String) -> Bool {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 3 && parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy { $0.isASCII && $0.isNumber } && (part == "0" || part.first != "0")
        }
    }

    /// The value of `KEY: "value"` (quotes optional), which must appear exactly once.
    private static func setting(_ key: String, in yml: String) throws(VersionError) -> String {
        let values = yml.split(separator: "\n").compactMap { line -> String? in
            let trimmed = line.drop { $0 == " " }
            guard trimmed.hasPrefix(key + ":") else { return nil }
            var value = trimmed.dropFirst(key.count + 1).drop { $0 == " " }
            if let comment = value.firstIndex(of: "#") { value = value[..<comment] }
            return String(value).trimmingCharacters(in: [" ", "\""])
        }
        guard let value = values.first else { throw .missing(key) }
        guard values.count == 1 else { throw .setTwice(key) }
        return value
    }
}

public enum VersionError: Error, Hashable, CustomStringConvertible {
    case missing(String)
    case setTwice(String)
    case badMarketing(String)
    case badBuild(String)
    case notAReleaseTag(String)
    case tagMismatch(tag: String, version: String)
    case buildNotAbove(build: Int, last: Int)

    public var description: String {
        switch self {
        case .missing(let key): "project.yml does not set \(key)"
        case .setTwice(let key): "project.yml sets \(key) more than once: the version lives in settings.base alone"
        case .badMarketing(let value): "MARKETING_VERSION \(value) is not X.Y.Z"
        case .badBuild(let value): "CURRENT_PROJECT_VERSION \(value) is not a whole number above nought"
        case .notAReleaseTag(let tag): "\(tag) is not a release tag: a release starts from v plus X.Y.Z alone"
        case .tagMismatch(let tag, let version): "\(tag) is not v plus project.yml's MARKETING_VERSION, \(version)"
        case .buildNotAbove(let build, let last): "build \(build) is not above \(last), the appcast's last: raise CURRENT_PROJECT_VERSION"
        }
    }
}

private extension String {
    func trimmingCharacters(in set: Set<Character>) -> String {
        String(drop { set.contains($0) }.reversed().drop { set.contains($0) }.reversed())
    }
}
