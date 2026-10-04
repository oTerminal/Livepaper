import Foundation
import ReleaseKit
import Testing

/// The release notes, the `## X.Y.Z` section of `CHANGELOG.md`, and the appcast:
/// one entry per release, kept for the app's life, newest build first.
struct ChangelogTests {
    static let changelog = """
        # Changelog

        What changed in each release. The section for a release is its notes, in the
        appcast and on GitHub.

        ## 1.0.1

        - Fixed: a scene paused behind a full-screen app stays paused.

        ## 1.0.0 — 2026-11-02

        The first release.

        - Live wallpapers on the desktop and the lock screen.
        - Updates through Sparkle.

        ## 0.9.0

        - The beta.
        """

    @Test func takesTheSectionOfOneVersion() throws {
        #expect(try Changelog.section(for: "1.0.0", in: Self.changelog) == """
            The first release.

            - Live wallpapers on the desktop and the lock screen.
            - Updates through Sparkle.
            """)
    }

    @Test func theLastSectionRunsToTheEnd() throws {
        #expect(try Changelog.section(for: "0.9.0", in: Self.changelog) == "- The beta.")
    }

    @Test func aVersionThatOnlyStartsLikeAnotherIsNotIt() {
        #expect(throws: ChangelogError.missing("1.0")) { try Changelog.section(for: "1.0", in: Self.changelog) }
        #expect(throws: ChangelogError.missing("0.1.0")) { try Changelog.section(for: "0.1.0", in: "## 0.1.0.1\n\n- no\n") }
    }

    @Test func aMissingSectionFails() {
        #expect(throws: ChangelogError.missing("2.0.0")) { try Changelog.section(for: "2.0.0", in: Self.changelog) }
    }

    @Test func anEmptySectionFails() {
        let changelog = "## 1.0.1\n\n- x\n\n## 1.0.0\n\n   \n## 0.9.0\n- y\n"
        #expect(throws: ChangelogError.empty("1.0.0")) { try Changelog.section(for: "1.0.0", in: changelog) }
    }

    @Test func aDoubledSectionFails() {
        let doubled = Self.changelog + "\n\n## 1.0.0\n\n- Again.\n"
        #expect(throws: ChangelogError.doubled("1.0.0")) { try Changelog.section(for: "1.0.0", in: doubled) }
    }
}

struct ReleaseNotesTests {
    @Test func paragraphsListsAndCodeBecomeHTML() {
        let markdown = """
            The first release.
            It plays loops.

            - Live wallpapers on the **desktop** and the lock screen.
            - Run `livepaper status` to see <what> it does & more.
            """
        #expect(ReleaseNotes.html(markdown: markdown) == """
            <p>The first release.
            It plays loops.</p>
            <ul>
            <li>Live wallpapers on the <strong>desktop</strong> and the lock screen.</li>
            <li>Run <code>livepaper status</code> to see &lt;what&gt; it does &amp; more.</li>
            </ul>
            """)
    }

    @Test func aSubheadingIsAHeading() {
        #expect(ReleaseNotes.html(markdown: "### Fixed\n\n- A crash.") == "<h3>Fixed</h3>\n<ul>\n<li>A crash.</li>\n</ul>")
    }

    @Test func aLinkStaysALink() {
        #expect(ReleaseNotes.html(markdown: "See [the README](https://github.com/oTerminal/Livepaper#install).")
            == #"<p>See <a href="https://github.com/oTerminal/Livepaper#install">the README</a>.</p>"#)
    }
}

struct AppcastTests {
    static let feed = URL(string: "https://oterminal.github.io/Livepaper/appcast.xml")!

    static func entry(build: Int, version: String) -> AppcastEntry {
        AppcastEntry(
            version: version,
            build: build,
            url: URL(string: "https://github.com/oTerminal/Livepaper/releases/download/v\(version)/Livepaper-\(version).zip")!,
            length: 30_000_000 + build,
            edSignature: "c2lnbmF0dXJlIG9mIGJ1aWxkIFwoYnVpbGQp+/\(build)==",
            minimumSystemVersion: "26.0",
            hardwareRequirements: "arm64",
            pubDate: "Mon, 02 Nov 2026 10:00:00 +0000",
            notesHTML: "<ul>\n<li>Build \(build) &amp; more.</li>\n</ul>"
        )
    }

    @Test func anEntryIsMadeFromItsParts() {
        let xml = Appcast(feedURL: Self.feed, entries: [Self.entry(build: 13, version: "1.0.1")]).xml
        #expect(xml.contains("<sparkle:version>13</sparkle:version>"))
        #expect(xml.contains("<sparkle:shortVersionString>1.0.1</sparkle:shortVersionString>"))
        #expect(xml.contains("<sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>"))
        #expect(xml.contains("<sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>"))
        #expect(xml.contains(
            #"<enclosure url="https://github.com/oTerminal/Livepaper/releases/download/v1.0.1/Livepaper-1.0.1.zip" length="30000013""#
                + #" type="application/octet-stream" sparkle:edSignature="c2lnbmF0dXJlIG9mIGJ1aWxkIFwoYnVpbGQp+/13=="/>"#
        ))
        #expect(xml.contains("<description><![CDATA[<ul>\n<li>Build 13 &amp; more.</li>\n</ul>]]></description>"))
        #expect(xml.contains("<link>https://oterminal.github.io/Livepaper/appcast.xml</link>"))
    }

    @Test func theFeedReadsBackAsTheEntriesItWasMadeFrom() throws {
        let entries = [Self.entry(build: 13, version: "1.0.1"), Self.entry(build: 12, version: "1.0.0")]
        let appcast = Appcast(feedURL: Self.feed, entries: entries)
        #expect(try Appcast(xml: appcast.xml) == appcast)
    }

    @Test func mergingKeepsOlderEntriesAndPutsTheNewestBuildFirst() throws {
        let old = Appcast(feedURL: Self.feed, entries: [Self.entry(build: 11, version: "0.9.1"), Self.entry(build: 12, version: "1.0.0")])
        let merged = try Appcast(xml: old.xml).merging(Self.entry(build: 13, version: "1.0.1"))
        #expect(merged.entries.map(\.build) == [13, 12, 11])
        #expect(merged.entries.dropFirst() == [Self.entry(build: 12, version: "1.0.0"), Self.entry(build: 11, version: "0.9.1")])
        #expect(merged.lastBuild == 13)
    }

    @Test func mergingRefusesABuildAlreadyInTheFeed() throws {
        let old = Appcast(feedURL: Self.feed, entries: [Self.entry(build: 12, version: "1.0.0")])
        #expect(throws: AppcastError.duplicateBuild(12)) { try old.merging(Self.entry(build: 12, version: "1.0.1")) }
    }

    @Test func mergingRefusesAVersionAlreadyInTheFeed() throws {
        let old = Appcast(feedURL: Self.feed, entries: [Self.entry(build: 12, version: "1.0.0")])
        #expect(throws: AppcastError.duplicateVersion("1.0.0")) { try old.merging(Self.entry(build: 13, version: "1.0.0")) }
    }

    @Test func anEmptyFeedHasNoLastBuild() {
        #expect(Appcast(feedURL: Self.feed, entries: []).lastBuild == nil)
    }

    /// What `generate_appcast` 2.10.0 writes for one archive: its signature and
    /// length are what a release takes from it.
    static let generated = """
        <?xml version="1.0" standalone="yes"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
            <channel>
                <title>Livepaper</title>
                <item>
                    <title>1.0.1</title>
                    <pubDate>Mon, 02 Nov 2026 10:00:00 +0000</pubDate>
                    <sparkle:version>13</sparkle:version>
                    <sparkle:shortVersionString>1.0.1</sparkle:shortVersionString>
                    <sparkle:minimumSystemVersion>26.0</sparkle:minimumSystemVersion>
                    <sparkle:hardwareRequirements>arm64</sparkle:hardwareRequirements>
                    <enclosure url="https://github.com/oTerminal/Livepaper/releases/download/v1.0.1/Livepaper-1.0.1.zip"
                        length="30000013" type="application/octet-stream"
                        sparkle:edSignature="c2lnbmF0dXJlIG9mIGJ1aWxkIFwoYnVpbGQp+/13=="/>
                </item>
            </channel>
        </rss>
        """

    @Test func readsTheEntryGenerateAppcastWrote() throws {
        let generated = try Appcast(xml: Self.generated)
        var expected = Self.entry(build: 13, version: "1.0.1")
        expected.notesHTML = ""
        #expect(generated.entries == [expected])
    }

    @Test func aFeedWithoutAnItemsSignatureIsRefused() {
        let unsigned = Self.generated.replacing(#/\s*sparkle:edSignature="[^"]*"/#, with: "")
        #expect(throws: AppcastError.incomplete("1.0.1")) { try Appcast(xml: unsigned) }
    }

    @Test func notesWithTheCDATAEndInsideThemSurviveTheRoundTrip() throws {
        var entry = Self.entry(build: 13, version: "1.0.1")
        entry.notesHTML = "<p>a ]]> b</p>"
        let appcast = Appcast(feedURL: Self.feed, entries: [entry])
        #expect(try Appcast(xml: appcast.xml).entries == [entry])
    }
}
