import Foundation
import LivepaperCore

/// Which of the two files an error is about. Never a path: diagnostics carry these.
nonisolated public enum WallpaperStoreFile: Equatable, Sendable {
    /// WallpaperAgent's own store.
    case store
    /// The store as it was before the first select, at `LibraryLocation.keptWallpaperStore`.
    case keptCopy
}

/// What about a file is not the shape this build knows.
nonisolated public enum WallpaperStoreProblem: Equatable, Sendable {
    /// Not a property list, or not a dictionary at its top.
    case notADictionary
    /// None of the places a wallpaper is set at: `SystemDefault`, `AllSpacesAndDisplays`, `Displays`, `Spaces`.
    case noPlaces
    /// A place that is not a dictionary, or a Desktop entry without content, choices, or a
    /// provider for each choice. Its keys, joined with dots: Space and display UUIDs, never a file.
    case unexpected(at: String)
}

nonisolated public enum WallpaperStoreError: Error, Equatable, Sendable {
    /// Missing, or could not be read.
    case unreadable(WallpaperStoreFile)
    case unknownShape(WallpaperStoreFile, WallpaperStoreProblem)
    /// Could not be written. The store is as it was: the new one is written beside it first.
    case notWritten(WallpaperStoreFile)
    /// Livepaper is still named, and no copy was kept: it was chosen by hand, or the copy has gone.
    case noKeptCopy
    /// An entry names Livepaper, and the kept copy has nothing else for it: neither in the same
    /// place nor for all Spaces and displays.
    case nothingToGoBackTo
}

/// What one edit of the store did.
nonisolated public struct WallpaperStoreEdit: Equatable, Sendable {
    /// Desktop entries rewritten. Zero means nothing was written.
    public var changed: Int
    /// Desktop entries in the store after the edit.
    public var desktopEntries: Int
    /// Whether the store as it was was kept first. Only a select keeps it.
    public var keptCopy: Bool

    public init(changed: Int, desktopEntries: Int, keptCopy: Bool = false) {
        self.changed = changed
        self.desktopEntries = desktopEntries
        self.keptCopy = keptCopy
    }

    public var wrote: Bool { changed > 0 }
}

/// What the wallpaper store says of Livepaper being the system wallpaper, as the host reads it
/// before restarting WallpaperAgent for silence.
nonisolated public enum StoreSelection: Equatable, Sendable {
    /// A Desktop entry names Livepaper: WallpaperAgent should be running the extension.
    case selected
    /// No Desktop entry names Livepaper: WallpaperAgent has no reason to launch the extension.
    case notSelected
    /// The store could not be read, or was not the shape expected: nothing can be told from it.
    case unreadable
}

/// The store's shape check, which the diagnostics report and the host read: numbers, never a
/// file list or a path.
nonisolated public struct WallpaperStoreShape: Equatable, Sendable, CustomStringConvertible {
    public enum Store: Equatable, Sendable {
        case read(desktopEntries: Int, namingLivepaper: Int)
        case unreadable
        case unknownShape
    }

    public var store: Store
    /// Whether the store as it was before Livepaper is kept, for leaving.
    public var keptCopyExists: Bool

    public init(store: Store, keptCopyExists: Bool) {
        self.store = store
        self.keptCopyExists = keptCopyExists
    }

    /// Whether any Desktop entry names Livepaper at all.
    public var selection: StoreSelection {
        switch store {
        case .read(_, let naming): naming > 0 ? .selected : .notSelected
        case .unreadable, .unknownShape: .unreadable
        }
    }

    /// "wallpaper store: 2 Desktop entries, 2 name Livepaper; kept copy: none".
    public var description: String {
        let kept = "kept copy: \(keptCopyExists ? "present" : "none")"
        switch store {
        case .read(let entries, let naming): return "wallpaper store: \(entries) Desktop entries, \(naming) name Livepaper; \(kept)"
        case .unreadable: return "wallpaper store: unreadable; \(kept)"
        case .unknownShape: return "wallpaper store: of a shape this build does not know; \(kept)"
        }
    }
}

/// The two edits Selection makes to the store, and the kept copy's end. `WallpaperStore` is
/// the real one; tests put a fake in its place.
public protocol WallpaperStoreEditing {
    func select(at now: Date) throws(WallpaperStoreError) -> WallpaperStoreEdit
    func deselect() throws(WallpaperStoreError) -> WallpaperStoreEdit
    func removeKeptCopy()
}

/// The store's shape check, which the host reads before restarting WallpaperAgent for silence and
/// never writes. `WallpaperStore` is the real one; tests put a fake in its place.
public protocol WallpaperStoreReading {
    func shape() -> WallpaperStoreShape
}

// In extensions, so that the store's own methods stay callable from any thread.
extension WallpaperStore: WallpaperStoreEditing {}
extension WallpaperStore: WallpaperStoreReading {}

/// WallpaperAgent's wallpaper store, and the edit that makes Livepaper the system wallpaper
/// and puts the previous one back.
///
/// Nothing public selects an extension's wallpaper, so Livepaper edits the store: an
/// undocumented property list in the user's Library, which needs no permission and no private
/// framework, and whose format can change with any macOS update. It is a tree: wherever a
/// wallpaper can be set (the system default, all Spaces and displays, one display, one Space,
/// one display in one Space) a place holds a Desktop entry and an Idle (screen saver) one.
/// Only Desktop entries are touched.
///
/// Every read checks the shape it expects and throws `WallpaperStoreError` rather than write
/// what it does not understand; the caller then opens the Wallpaper pane. Every write is the
/// whole tree, edited entry by entry, written beside the store and renamed over it, so that
/// WallpaperAgent never reads half a store. A copy is never put back whole: that would undo
/// whatever the user changed since.
nonisolated public struct WallpaperStore: Sendable {
    /// WallpaperAgent's store.
    public let file: URL
    /// The store as it was before the first select.
    public let keptCopy: URL
    /// What every Desktop entry names once Livepaper is selected: the extension's bundle identifier,
    /// and its one choice's identifier as the configuration.
    public let provider: String
    public let configuration: Data

    /// Where WallpaperAgent keeps the store for the user whose home this is.
    public static func file(home: URL) -> URL {
        home.appending(path: "Library/Application Support/com.apple.wallpaper/Store/Index.plist", directoryHint: .notDirectory)
    }

    /// The real store and the kept copy in the library. The app is not sandboxed, so `home` is the user's.
    public init(home: URL) {
        self.init(file: Self.file(home: home), keptCopy: LibraryLocation(home: home).keptWallpaperStore)
    }

    public init(
        file: URL,
        keptCopy: URL,
        provider: String = WallpaperExtensionIdentity.bundleIdentifier,
        choice: String = WallpaperExtensionIdentity.choiceIdentifier
    ) {
        self.file = file
        self.keptCopy = keptCopy
        self.provider = provider
        configuration = Data(choice.utf8)
    }

    /// Makes every Desktop entry name Livepaper; a store with none gets one at `SystemDefault`.
    /// Nothing is written when every entry names it already.
    ///
    /// The store is kept first when it names Livepaper nowhere, since it is then the user's own
    /// choice and replaces any older copy, or when no copy is kept yet. A store that is half
    /// Livepaper already keeps the copy from before.
    @discardableResult
    public func select(at now: Date) throws(WallpaperStoreError) -> WallpaperStoreEdit {
        let (data, root) = try read(.store)
        let entries = try Self.desktopEntries(in: root, of: .store)
        let naming = entries.count { $0.provider == provider }
        if !entries.isEmpty, naming == entries.count {
            return WallpaperStoreEdit(changed: 0, desktopEntries: entries.count)
        }
        let keep = naming == 0 || !FileManager.default.fileExists(atPath: keptCopy.path)
        if keep { try write(data, to: .keptCopy) }

        let entry = livepaperEntry(at: now)
        var tree = root
        var changed = 0
        for existing in entries where existing.provider != provider {
            tree = Self.setting(entry, at: existing.place + ["Desktop"], in: tree)
            changed += 1
        }
        if entries.isEmpty {
            var systemDefault = tree["SystemDefault"] as? Node ?? [:]
            systemDefault["Type"] = systemDefault["Type"] ?? "individual"
            systemDefault["Desktop"] = entry
            tree["SystemDefault"] = systemDefault
            changed = 1
        }
        try write(Self.encode(tree), to: .store)
        return WallpaperStoreEdit(changed: changed, desktopEntries: max(entries.count, 1), keptCopy: keep)
    }

    /// Wherever a Desktop entry still names Livepaper, puts back what the kept copy has in the
    /// same place, or else its entry for all Spaces and displays, or else its system default: a
    /// Space made since select has no place of its own there, and would have shown the one for
    /// all Spaces. Entries the user has changed since are left alone. Nothing is written when
    /// Livepaper is named nowhere; nothing at all when one entry has nothing to go back to.
    @discardableResult
    public func deselect() throws(WallpaperStoreError) -> WallpaperStoreEdit {
        let (_, root) = try read(.store)
        let entries = try Self.desktopEntries(in: root, of: .store)
        let naming = entries.filter { $0.provider == provider }
        guard !naming.isEmpty else { return WallpaperStoreEdit(changed: 0, desktopEntries: entries.count) }
        guard FileManager.default.fileExists(atPath: keptCopy.path) else { throw .noKeptCopy }

        let (_, kept) = try read(.keptCopy)
        let before = Dictionary(
            try Self.desktopEntries(in: kept, of: .keptCopy).filter { $0.provider != provider }.map { ($0.place, $0.node) },
            uniquingKeysWith: { first, _ in first }
        )
        let fallback = before[["AllSpacesAndDisplays"]] ?? before[["SystemDefault"]]
        var tree = root
        for entry in naming {
            guard let previous = before[entry.place] ?? fallback else { throw .nothingToGoBackTo }
            tree = Self.setting(previous, at: entry.place + ["Desktop"], in: tree)
        }
        try write(Self.encode(tree), to: .store)
        return WallpaperStoreEdit(changed: naming.count, desktopEntries: entries.count)
    }

    /// After a leave: the copy has done its work, and a next select keeps a new one.
    public func removeKeptCopy() {
        try? FileManager.default.removeItem(at: keptCopy)
    }

    /// For the diagnostics, and for the host before it restarts WallpaperAgent for silence: how
    /// many Desktop entries there are, how many name Livepaper, and whether a copy is kept. Reads,
    /// and never writes.
    public func shape() -> WallpaperStoreShape {
        let kept = FileManager.default.fileExists(atPath: keptCopy.path)
        do throws(WallpaperStoreError) {
            let entries = try Self.desktopEntries(in: read(.store).root, of: .store)
            let naming = entries.count { $0.provider == provider }
            return WallpaperStoreShape(store: .read(desktopEntries: entries.count, namingLivepaper: naming), keptCopyExists: kept)
        } catch .unreadable {
            return WallpaperStoreShape(store: .unreadable, keptCopyExists: kept)
        } catch {
            return WallpaperStoreShape(store: .unknownShape, keptCopyExists: kept)
        }
    }

    /// The Desktop entry naming Livepaper, in the form WallpaperAgent writes when Livepaper is
    /// chosen in System Settings, dates aside (the store on the development Mac, 2026-09-24).
    func livepaperEntry(at now: Date) -> Node {
        let choice: Node = ["Provider": provider, "Files": [Any](), "Configuration": configuration]
        let content: Node = ["Choices": [choice], "Shuffle": "$null", "EncodedOptionValues": Self.noOptionValues]
        return ["Content": content, "LastSet": now, "LastUse": now]
    }

    /// `EncodedOptionValues` for a choice with no options: an empty `values` dictionary as a
    /// binary property list, the agent's own 54 bytes for Livepaper. The spike wrote `$null`,
    /// which the agent also took, but the agent's own form is what a click in the pane leaves.
    static let noOptionValues =
        (try? PropertyListSerialization.data(fromPropertyList: ["values": Node()], format: .binary, options: 0)) ?? Data()

    // MARK: Reading and writing

    private func url(of which: WallpaperStoreFile) -> URL {
        which == .store ? file : keptCopy
    }

    /// The file's bytes and its tree, once its top has been checked.
    private func read(_ which: WallpaperStoreFile) throws(WallpaperStoreError) -> (data: Data, root: Node) {
        guard let data = try? Data(contentsOf: url(of: which)) else { throw .unreadable(which) }
        guard let root = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? Node else {
            throw .unknownShape(which, .notADictionary)
        }
        let places = Self.places.filter { root[$0] != nil }
        guard !places.isEmpty else { throw .unknownShape(which, .noPlaces) }
        if let odd = places.first(where: { !(root[$0] is Node) }) { throw .unknownShape(which, .unexpected(at: odd)) }
        return (data, root)
    }

    private static func encode(_ tree: Node) throws(WallpaperStoreError) -> Data {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: tree, format: .binary, options: 0) else {
            throw .notWritten(.store)
        }
        return data
    }

    /// Writes a new file beside the old one and renames it over, on the same volume: whoever
    /// reads the file meanwhile gets the old one or the new one, never half of either.
    private func write(_ data: Data, to which: WallpaperStoreFile) throws(WallpaperStoreError) {
        let target = url(of: which)
        let folder = target.deletingLastPathComponent()
        let temporary = folder.appending(path: ".\(target.lastPathComponent).\(UUID().uuidString)", directoryHint: .notDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: temporary, options: .withoutOverwriting)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw .notWritten(which)
        }
        guard rename(temporary.path, target.path) == 0 else {
            try? FileManager.default.removeItem(at: temporary)
            throw .notWritten(which)
        }
    }
}
