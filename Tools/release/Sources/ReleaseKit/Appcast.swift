import Foundation

/// One release in the appcast: what Sparkle needs to offer it and check it.
public struct AppcastEntry: Hashable, Sendable {
    /// `CFBundleShortVersionString`, `X.Y.Z`; the item's title too.
    public var version: String
    /// `CFBundleVersion`, which Sparkle orders updates by.
    public var build: Int
    /// The zip on the release.
    public var url: URL
    public var length: Int
    /// The zip's EdDSA signature, from `generate_appcast`.
    public var edSignature: String
    public var minimumSystemVersion: String?
    /// `arm64`: Sparkle offers the update to no other Mac.
    public var hardwareRequirements: String?
    /// RFC 822, as RSS has it.
    public var pubDate: String
    /// The changelog section as HTML; empty in what `generate_appcast` writes.
    public var notesHTML: String

    public init(
        version: String, build: Int, url: URL, length: Int, edSignature: String,
        minimumSystemVersion: String?, hardwareRequirements: String?, pubDate: String, notesHTML: String
    ) {
        self.version = version
        self.build = build
        self.url = url
        self.length = length
        self.edSignature = edSignature
        self.minimumSystemVersion = minimumSystemVersion
        self.hardwareRequirements = hardwareRequirements
        self.pubDate = pubDate
        self.notesHTML = notesHTML
    }
}

/// `appcast.xml`: one feed for the app's life, every release in it, newest build first.
public struct Appcast: Hashable, Sendable {
    public var feedURL: URL?
    public var entries: [AppcastEntry]

    public init(feedURL: URL?, entries: [AppcastEntry]) {
        self.feedURL = feedURL
        self.entries = entries
    }

    /// Reads a feed: ours, or the one `generate_appcast` writes.
    public init(xml: String) throws(AppcastError) {
        let document: XMLDocument
        do {
            document = try XMLDocument(xmlString: xml, options: [.nodePreserveCDATA])
        } catch {
            throw .unreadable
        }
        guard let channel = document.rootElement()?.elements(forName: "channel").first else { throw .unreadable }
        feedURL = channel.elements(forName: "link").first?.stringValue.flatMap(URL.init(string:))
        entries = []
        for item in channel.elements(forName: "item") {
            entries.append(try Self.entry(from: item))
        }
    }

    /// The highest build in the feed; nil before the first release.
    public var lastBuild: Int? { entries.map(\.build).max() }

    /// The feed with one more release, newest build first. A build or a version the
    /// feed has already is refused: a release is never published twice.
    public func merging(_ entry: AppcastEntry) throws(AppcastError) -> Appcast {
        if entries.contains(where: { $0.build == entry.build }) { throw .duplicateBuild(entry.build) }
        if entries.contains(where: { $0.version == entry.version }) { throw .duplicateVersion(entry.version) }
        var merged = self
        merged.entries.append(entry)
        merged.entries.sort { $0.build > $1.build }
        return merged
    }

    public var xml: String {
        var lines = [
            #"<?xml version="1.0" encoding="utf-8"?>"#,
            #"<rss version="2.0" xmlns:sparkle="\#(Self.sparkleNamespace)">"#,
            "  <channel>",
            "    <title>Livepaper</title>",
        ]
        if let feedURL { lines.append("    <link>\(ReleaseNotes.escape(feedURL.absoluteString))</link>") }
        lines += [
            "    <description>Livepaper's updates.</description>",
            "    <language>en</language>",
        ]
        for entry in entries {
            lines += [
                "    <item>",
                "      <title>\(ReleaseNotes.escape(entry.version))</title>",
                "      <pubDate>\(ReleaseNotes.escape(entry.pubDate))</pubDate>",
                "      <sparkle:version>\(entry.build)</sparkle:version>",
                "      <sparkle:shortVersionString>\(ReleaseNotes.escape(entry.version))</sparkle:shortVersionString>",
            ]
            if let minimum = entry.minimumSystemVersion {
                lines.append("      <sparkle:minimumSystemVersion>\(ReleaseNotes.escape(minimum))</sparkle:minimumSystemVersion>")
            }
            if let hardware = entry.hardwareRequirements {
                lines.append("      <sparkle:hardwareRequirements>\(ReleaseNotes.escape(hardware))</sparkle:hardwareRequirements>")
            }
            // A "]]>" inside the notes ends one CDATA section and starts the next.
            let notes = entry.notesHTML.replacingOccurrences(of: "]]>", with: "]]]]><![CDATA[>")
            lines += [
                "      <description><![CDATA[\(notes)]]></description>",
                #"      <enclosure url="\#(ReleaseNotes.escape(entry.url.absoluteString))" length="\#(entry.length)""#
                    + #" type="application/octet-stream" sparkle:edSignature="\#(ReleaseNotes.escape(entry.edSignature))"/>"#,
                "    </item>",
            ]
        }
        lines += ["  </channel>", "</rss>", ""]
        return lines.joined(separator: "\n")
    }

    static let sparkleNamespace = "http://www.andymatuschak.org/xml-namespaces/sparkle"

    private static func entry(from item: XMLElement) throws(AppcastError) -> AppcastEntry {
        func text(_ name: String) -> String? {
            item.elements(forLocalName: name, uri: sparkleNamespace).first?.stringValue
                ?? item.elements(forName: name).first?.stringValue
        }
        let enclosure = item.elements(forName: "enclosure").first
        let version = text("shortVersionString") ?? text("title") ?? "?"
        guard
            let build = text("version").flatMap({ Int($0) }),
            let url = enclosure?.attribute(forName: "url")?.stringValue.flatMap(URL.init(string:)),
            let length = enclosure?.attribute(forName: "length")?.stringValue.flatMap({ Int($0) }),
            let signature = enclosure?.attribute(forLocalName: "edSignature", uri: sparkleNamespace)?.stringValue,
            !signature.isEmpty
        else { throw .incomplete(version) }
        return AppcastEntry(
            version: version,
            build: build,
            url: url,
            length: length,
            edSignature: signature,
            minimumSystemVersion: text("minimumSystemVersion"),
            hardwareRequirements: text("hardwareRequirements"),
            pubDate: text("pubDate") ?? "",
            notesHTML: text("description") ?? ""
        )
    }
}

public enum AppcastError: Error, Hashable, CustomStringConvertible {
    case unreadable
    case incomplete(String)
    case duplicateBuild(Int)
    case duplicateVersion(String)

    public var description: String {
        switch self {
        case .unreadable: "the appcast is not an RSS feed"
        case .incomplete(let version):
            "the appcast's \(version) entry lacks its build, enclosure or EdDSA signature "
                + "(generate_appcast signs nothing when the private key is not the app's SUPublicEDKey)"
        case .duplicateBuild(let build): "the appcast has build \(build) already"
        case .duplicateVersion(let version): "the appcast has version \(version) already"
        }
    }
}
