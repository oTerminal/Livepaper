import Foundation

// The store's tree, as the spike found it on two real stores and as the development Mac's
// store has it (Tests/LivepaperSystemTests/Fixtures): `SystemDefault` and `AllSpacesAndDisplays`
// are places; `Displays` holds a place per display UUID; `Spaces` holds, per Space UUID, a
// `Default` place and a `Displays` of places. A place holds `Desktop`, `Idle` and `Type`.
// Desktop entries are found wherever they are, not only at those places, so that a new kind of
// place is rewritten too rather than left showing the old wallpaper.

nonisolated extension WallpaperStore {
    /// A dictionary of the store's property list.
    typealias Node = [String: Any]

    /// A Desktop entry, the keys of the place that holds it, and what its first choice names.
    struct Entry {
        var place: [String]
        var node: Node
        var provider: String
    }

    /// The places at the top of the tree; a store with none of them is not one this build knows.
    static let places = ["SystemDefault", "AllSpacesAndDisplays", "Displays", "Spaces"]

    /// Every Desktop entry in the tree, each checked, in the order of their places.
    static func desktopEntries(in root: Node, of which: WallpaperStoreFile) throws(WallpaperStoreError) -> [Entry] {
        var found: [Entry] = []
        try collect(root, place: [], into: &found, of: which)
        return found.sorted { $0.place.lexicographicallyPrecedes($1.place) }
    }

    /// Idle entries are not looked into: the edit never touches the screen saver.
    private static func collect(
        _ node: Node, place: [String], into found: inout [Entry], of which: WallpaperStoreFile
    ) throws(WallpaperStoreError) {
        for (key, value) in node {
            switch key {
            case "Desktop":
                guard let entry = value as? Node, let provider = provider(of: entry) else {
                    throw .unknownShape(which, .unexpected(at: (place + [key]).joined(separator: ".")))
                }
                found.append(Entry(place: place, node: entry, provider: provider))
            case "Idle":
                continue
            default:
                if let child = value as? Node { try collect(child, place: place + [key], into: &found, of: which) }
            }
        }
    }

    /// What an entry's first choice names, when the entry has the form the agent writes: a
    /// `Content` whose `Choices` are one or more dictionaries, each with a `Provider`.
    static func provider(of entry: Node) -> String? {
        guard let content = entry["Content"] as? Node, let choices = content["Choices"] as? [Any], !choices.isEmpty else { return nil }
        let providers = choices.compactMap { ($0 as? Node)?["Provider"] as? String }
        return providers.count == choices.count ? providers.first : nil
    }

    /// The tree with `value` at the end of `path`, every node on the way copied.
    static func setting(_ value: Any, at path: [String], in node: Node) -> Node {
        var node = node
        guard let key = path.first else { return node }
        node[key] = path.count == 1 ? value : setting(value, at: Array(path.dropFirst()), in: node[key] as? Node ?? [:])
        return node
    }
}
