import Foundation
import Testing

/// Copies of real wallpaper stores and stores built in their shape, checked in
/// with `Fixtures/README.md` saying where each came from.
enum Fixture {
    static let livepaper = "wallpaper-store-livepaper"
    static let aerial = "wallpaper-store-aerial"
    static let idleOnly = "wallpaper-store-idle-only"
    static let spaces = "wallpaper-store-spaces"

    static func url(_ name: String) throws -> URL {
        try #require(
            Bundle.module.url(forResource: name, withExtension: "plist", subdirectory: "Fixtures"),
            "no fixture named \(name).plist"
        )
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: url(name))
    }
}

/// A store's property list, read for comparing and taken apart by key.
struct StoreTree: Equatable, CustomStringConvertible {
    let root: [String: Any]

    init(_ root: [String: Any]) {
        self.root = root
    }

    init(data: Data) throws {
        root = try #require(try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }

    init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url))
    }

    static func == (lhs: StoreTree, rhs: StoreTree) -> Bool {
        NSDictionary(dictionary: lhs.root).isEqual(to: rhs.root)
    }

    var description: String { NSDictionary(dictionary: root).description }

    /// The dictionary at the end of `path`, if there is one.
    func node(_ path: [String]) -> [String: Any]? {
        var node: [String: Any]? = root
        for key in path { node = node?[key] as? [String: Any] }
        return node
    }

    /// Every entry under `key` ("Desktop" or "Idle"), by the keys of the place that holds it, joined with dots.
    func entries(_ key: String) -> [String: [String: Any]] {
        var found: [String: [String: Any]] = [:]
        func walk(_ node: [String: Any], _ place: [String]) {
            for (name, value) in node {
                guard let child = value as? [String: Any] else { continue }
                if name == key {
                    found[place.joined(separator: ".")] = child
                } else if name != "Desktop", name != "Idle" {
                    walk(child, place + [name])
                }
            }
        }
        walk(root, [])
        return found
    }

    /// What each Desktop entry's first choice names, by place.
    var desktopProviders: [String: String] {
        entries("Desktop").compactMapValues { entry in
            (((entry["Content"] as? [String: Any])?["Choices"] as? [Any])?.first as? [String: Any])?["Provider"] as? String
        }
    }

    /// A tree with `value` at the end of `path`.
    func setting(_ value: Any?, at path: [String]) -> StoreTree {
        func set(_ node: [String: Any], _ path: ArraySlice<String>) -> [String: Any] {
            var node = node
            guard let key = path.first else { return node }
            node[key] = path.count == 1 ? value : set(node[key] as? [String: Any] ?? [:], path.dropFirst())
            return node
        }
        return StoreTree(set(root, path[...]))
    }

    func data() throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: root, format: .binary, options: 0)
    }
}
