import Foundation

/// Wallpaper Engine's app on Steam. Only an account that owns it can download
/// its Workshop items.
public let wallpaperEngineApp: UInt64 = 431_960

/// A Workshop item's number, as Steam gives it: a positive 64-bit number.
public struct WorkshopItemID: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public let value: UInt64

    public init?(_ value: UInt64) {
        guard value > 0 else { return nil }
        self.value = value
    }

    /// Plain decimal digits and nothing else: no sign, no space, no leading zero.
    public init?(_ text: some StringProtocol) {
        guard let first = text.first, first != "0", text.allSatisfy(\.isASCIIDigit), let value = UInt64(text) else { return nil }
        self.init(value)
    }

    public var description: String { String(value) }

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.value < rhs.value }
}

/// The Workshop's pages, and the links that name an item.
public enum WorkshopLink {
    /// Where the Workshop window opens: Wallpaper Engine's Workshop on Steam Community.
    public static let front = URL(string: "https://steamcommunity.com/app/431960/workshop/")!

    /// An item's page on Steam Community.
    public static func page(of item: WorkshopItemID) -> URL {
        URL(string: "https://steamcommunity.com/sharedfiles/filedetails/?id=\(item)")!
    }

    /// The item a link is to: an item's page on Steam Community, or Steam's own
    /// `steam://url/CommunityFilePage/<id>`. Anything else is nil, a page on a
    /// host that only looks like Steam's included.
    public static func item(in url: URL) -> WorkshopItemID? {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        switch parts.scheme?.lowercased() {
        case "steam":
            // steam://url/CommunityFilePage/<id>: the host is "url".
            let steps = parts.path.split(separator: "/", omittingEmptySubsequences: true)
            guard parts.host?.lowercased() == "url", steps.count == 2, steps[0] == "CommunityFilePage" else { return nil }
            return WorkshopItemID(steps[1])
        case "http", "https":
            guard isCommunity(parts) else { return nil }
            let path = parts.path.hasSuffix("/") ? String(parts.path.dropLast()) : parts.path
            guard ["/sharedfiles/filedetails", "/workshop/filedetails"].contains(path) else { return nil }
            let ids = (parts.queryItems ?? []).filter { $0.name == "id" }
            guard ids.count == 1, let id = ids[0].value else { return nil }
            return WorkshopItemID(id)
        default:
            return nil
        }
    }

    /// The item pasted text names: a link to it, or its number alone, with
    /// nothing else but space around it.
    public static func item(inPasted text: String) -> WorkshopItemID? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = WorkshopItemID(trimmed) { return id }
        guard !trimmed.contains(where: \.isWhitespace), let url = URL(string: trimmed) else { return nil }
        return item(in: url)
    }

    /// What the Workshop window does with a page the user goes to.
    public enum Navigation: Equatable, Sendable {
        /// A page of Steam Community, over https: shown in the window.
        case inWindow
        /// Any other web page, such as a link out of an item's description: opened in the user's browser.
        case inBrowser
        /// Scripts, files, data and Steam's own links: not followed.
        case refused
    }

    public static func navigation(to url: URL) -> Navigation {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return .refused }
        switch parts.scheme?.lowercased() {
        case "https" where isCommunity(parts): return .inWindow
        case "http", "https": return parts.host == nil ? .refused : .inBrowser
        default: return .refused
        }
    }

    /// Steam Community itself: its own host, with no name, password or port of its own.
    private static func isCommunity(_ parts: URLComponents) -> Bool {
        guard parts.user == nil, parts.password == nil, parts.port == nil, let host = parts.host?.lowercased() else { return false }
        return host == "steamcommunity.com" || host == "www.steamcommunity.com"
    }
}

extension Character {
    fileprivate var isASCIIDigit: Bool { isASCII && isWholeNumber }
}
