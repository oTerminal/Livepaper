import Foundation
import LivepaperImport

/// Why Livepaper will not download an item, known from its page before any download.
public enum WorkshopRefusal: Equatable, Sendable {
    /// The page is another app's Workshop item.
    case notWallpaperEngine
    /// What discovery would say of the downloaded folder: a web or application item.
    case skipped(SkipReason)

    public var words: String {
        switch self {
        case .notWallpaperEngine: workshopFailureWords(.notWallpaperEngine).reason
        case .skipped(let reason): skipWords(reason)
        }
    }
}

/// What a Workshop item's page on Steam Community says about the item: its app,
/// its title, its type tag and its preview picture. Read from the page's HTML,
/// which the Workshop window has loaded and a pasted link fetches; nothing is
/// run. A page that is not an item's reads as nothing.
public struct WorkshopItemPage: Equatable, Sendable {
    /// The Steam app whose Workshop it is in, from the page's breadcrumbs.
    public var app: UInt64?
    public var title: String?
    /// The "Type" tag: Scene, Video, Web, Application and so on.
    public var type: String?
    /// The item's preview picture, on https only.
    public var preview: URL?

    public init(app: UInt64?, title: String?, type: String?, preview: URL?) {
        self.app = app
        self.title = title
        self.type = type
        self.preview = preview
    }

    public init(html: String) {
        title = html.firstMatch(of: /<title>Steam Workshop::([^<]*)<\/title>/).map { decodingEntities(String($0.1)) }
        app = html.firstMatch(of: /class="breadcrumbs">\s*<a[^>]*href="https:\/\/steamcommunity\.com\/app\/(\d+)"/).flatMap { UInt64($0.1) }
        type = html.firstMatch(of: /<span class="workshopTagsTitle">Type:&nbsp;<\/span>\s*<a[^>]*>([^<]*)<\/a>/)
            .map { decodingEntities(String($0.1)) }
        preview = html.firstMatch(of: /id="previewImage(?:Main)?"[^>]*\ssrc="([^"]+)"/)
            .flatMap { URL(string: decodingEntities(String($0.1))) }
            .flatMap { $0.scheme == "https" ? $0 : nil }
    }

    /// What would be refused anyway, known before any download. Nil when the page does not say.
    public var refusal: WorkshopRefusal? {
        if let app, app != wallpaperEngineApp { return .notWallpaperEngine }
        switch type?.lowercased() {
        case "web": return .skipped(.wallpaperEngine(.runsCode("web")))
        case "application": return .skipped(.wallpaperEngine(.runsCode("application")))
        default: return nil
        }
    }
}

/// The entities Steam's pages use in titles and links.
private func decodingEntities(_ text: String) -> String {
    var decoded = text
    for (entity, character) in [("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", " ")] {
        decoded = decoded.replacingOccurrences(of: entity, with: character)
    }
    // Last, so that "&amp;lt;" becomes "&lt;" and not "<".
    return decoded.replacingOccurrences(of: "&amp;", with: "&")
}
