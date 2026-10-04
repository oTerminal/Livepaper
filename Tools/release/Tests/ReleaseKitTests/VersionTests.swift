import ReleaseKit
import Testing

/// The version rules: `project.yml` holds the version, the tag is `v` plus it and
/// nothing else starts a release, and each release's build is above the feed's last.
struct VersionTests {
    static let version = ReleaseVersion(marketing: "1.0.0", build: 12)

    static let tags: [Row<String, VersionError?>] = [
        Row("v1.0.0 matches 1.0.0", "v1.0.0", nil),
        Row("1.0.0 without the v starts nothing", "1.0.0", .notAReleaseTag("1.0.0")),
        Row("v1.0 starts nothing", "v1.0", .notAReleaseTag("v1.0")),
        Row("v1.0.0-beta.1 starts nothing", "v1.0.0-beta.1", .notAReleaseTag("v1.0.0-beta.1")),
        Row("a tag ref is read as its tag", "refs/tags/v1.0.0", nil),
        Row("another release's tag does not match", "v1.0.1", .tagMismatch(tag: "v1.0.1", version: "1.0.0")),
        Row("v01.0.0 is not v1.0.0", "v01.0.0", .notAReleaseTag("v01.0.0")),
    ]

    @Test(arguments: tags)
    func aTagStartsThisReleaseOnlyWhenItIsVPlusTheVersion(_ row: Row<String, VersionError?>) {
        #expect(refusal { () throws(VersionError) in try Self.version.check(tag: row.input) } == row.expected)
    }

    static let builds: [Row<Int?, VersionError?>] = [
        Row("the first release, with no feed yet", nil, nil),
        Row("12 after 11", 11, nil),
        Row("12 after 12 is refused", 12, .buildNotAbove(build: 12, last: 12)),
        Row("12 after 13 is refused", 13, .buildNotAbove(build: 12, last: 13)),
    ]

    @Test(arguments: builds)
    func aBuildMustBeAboveTheFeedsLast(_ row: Row<Int?, VersionError?>) {
        #expect(refusal { () throws(VersionError) in try Self.version.check(after: row.input) } == row.expected)
    }

    @Test func thirteenAfterTwelveIsAccepted() throws {
        try ReleaseVersion(marketing: "1.0.1", build: 13).check(after: 12)
    }

    static let project = """
        settings:
          base:
            SWIFT_VERSION: "6.0"
            MARKETING_VERSION: "1.0.0"
            CURRENT_PROJECT_VERSION: "12"
            CODE_SIGN_IDENTITY: "-"
        """

    @Test func readsTheVersionFromProjectYML() throws {
        #expect(try ReleaseVersion(projectYML: Self.project) == Self.version)
    }

    static let badProjects: [Row<String, VersionError>] = [
        Row("no marketing version", "    CURRENT_PROJECT_VERSION: \"12\"\n", .missing("MARKETING_VERSION")),
        Row("no build", "    MARKETING_VERSION: \"1.0.0\"\n", .missing("CURRENT_PROJECT_VERSION")),
        Row(
            "a version set twice, as a target would",
            project + "\n        MARKETING_VERSION: \"1.0.1\"\n", .setTwice("MARKETING_VERSION")
        ),
        Row(
            "a marketing version that is not X.Y.Z",
            "    MARKETING_VERSION: \"1.0\"\n    CURRENT_PROJECT_VERSION: \"12\"\n", .badMarketing("1.0")
        ),
        Row(
            "a build that is not a whole number",
            "    MARKETING_VERSION: \"1.0.0\"\n    CURRENT_PROJECT_VERSION: \"12.1\"\n", .badBuild("12.1")
        ),
        Row("a build of nought", "    MARKETING_VERSION: \"1.0.0\"\n    CURRENT_PROJECT_VERSION: \"0\"\n", .badBuild("0")),
    ]

    @Test(arguments: badProjects)
    func refusesAVersionItCannotTrust(_ row: Row<String, VersionError>) {
        #expect(throws: row.expected) { try ReleaseVersion(projectYML: row.input) }
    }
}

/// What a check refused, or nil when it passed.
func refusal<Failure: Error>(_ check: () throws(Failure) -> Void) -> Failure? {
    do {
        try check()
        return nil
    } catch {
        return error
    }
}
