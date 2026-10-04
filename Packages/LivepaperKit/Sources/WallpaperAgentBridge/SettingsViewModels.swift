// The Codable shims for the settings view models and the archive class remap are
// adapted from Phosphene's CodableShims.swift and SettingsProvider.swift (MIT,
// (c) 2026 kageroumado, https://github.com/kageroumado/phosphene); see NOTICE at
// the repository root.

import Foundation
import LivepaperCore
import os

/// The one entry Livepaper has in System Settings > Wallpaper: one group with
/// one item, "Livepaper", whose choice is `WallpaperExtensionIdentity.choiceIdentifier`.
/// The wallpaper store keys the user's selection by the provider and carries
/// the choice as its configuration.
public struct SettingsEntry: Sendable {
    /// The extension's bundle identifier.
    public var provider: String
    /// The tile's picture: a PNG that WallpaperAgent can read, such as a
    /// resource in the extension's bundle. The extension writes no file.
    public var tile: URL

    public init(provider: String, tile: URL) {
        self.provider = provider
        self.tile = tile
    }

    static let name = "Livepaper"
    static let summary = "Your live wallpaper"

    /// The view models, as the Codable shims.
    var viewModels: SettingsViewModels {
        let choice = WallpaperExtensionIdentity.choiceIdentifier
        let provider = ChoiceProviderID(rawValue: provider)
        let choiceID = ChoiceID(
            id: choice,
            descriptor: ChoiceIDDescriptor(provider: provider, identifier: choice, files: [], configuration: Data(choice.utf8))
        )
        let item = SettingsItem(
            id: choiceID, localizedName: Self.name, thumbnail: .image(url: tile),
            choice: ChoiceDescriptor(
                id: choiceID, provider: provider, identifier: choice, name: Self.name,
                localizedDescription: Self.summary, thumbnail: .image(url: tile), isDownloaded: true, options: []
            ),
            contentBadge: .video, showInTopLevel: true, sortOrder: 0, disposability: .none, contextMenu: nil
        )
        let group = SettingsGroup(
            id: GroupID(id: choice), items: [item], localizedName: Self.name, disposability: .none, sortOrder: -100,
            sortID: GroupSortID(id: "com.apple.wallpaper.aerials"), allChoiceID: nil, shouldHideItemLabels: false,
            contextMenu: nil, thumbnail: nil
        )
        let model = SettingsViewModel(groups: [group], refreshPolicy: .default, isModificationDisabled: false)
        return SettingsViewModels(desktop: model, screenSaver: model)
    }

    /// The private `WallpaperSettingsViewModelsXPC`, made by archiving the shim
    /// and decoding the archive as that class. Secure coding is off for the
    /// class substitution; the archive never leaves this function.
    func reply() -> AnyObject? {
        guard let real = objc_getClass(Self.replyClassName) as? AnyClass,
              let data = try? NSKeyedArchiver.archivedData(
                  withRootObject: SettingsViewModelsShim(viewModels), requiringSecureCoding: false
              ),
              let unarchiver = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        unarchiver.requiresSecureCoding = false
        unarchiver.decodingFailurePolicy = .setErrorAndReturn
        unarchiver.setClass(real, forClassName: SettingsViewModelsShim.archivedName)
        let result = unarchiver.decodeObject(forKey: NSKeyedArchiveRootObjectKey)
        unarchiver.finishDecoding()
        return result as AnyObject?
    }

    static let replyClassName = "WallpaperSettingsViewModelsXPC"
}

/// Encodes the shim under the key the real `WallpaperSettingsViewModelsXPC` reads.
@objc(LivepaperSettingsViewModelsShim)
final class SettingsViewModelsShim: NSObject, NSSecureCoding {
    static let archivedName = "LivepaperSettingsViewModelsShim"
    static var supportsSecureCoding: Bool { true }

    let value: SettingsViewModels

    init(_ value: SettingsViewModels) {
        self.value = value
    }

    required init?(coder: NSCoder) { nil }

    func encode(with coder: NSCoder) {
        do {
            try (coder as? NSKeyedArchiver)?.encodeEncodable(value, forKey: "WallpaperSettingsViewModels")
        } catch {
            Logger.bridge.error("bridge: settings view models could not be encoded: \(error.localizedDescription, privacy: .public)")
        }
    }
}

// These follow the Codable layout of the private WallpaperTypes structs closely
// enough that the real decoder takes them. Only the cases Livepaper uses are modelled.

struct SettingsViewModels: Codable {
    var desktop: SettingsViewModel?
    var screenSaver: SettingsViewModel?
}

struct SettingsViewModel: Codable {
    var groups: [SettingsGroup]
    var refreshPolicy: RefreshPolicy
    var isModificationDisabled: Bool
}

struct GroupID: Codable {
    var id: String
}

struct GroupSortID: Codable {
    var id: String
}

struct ChoiceID: Codable {
    var id: String
    var descriptor: ChoiceIDDescriptor
}

struct ChoiceIDDescriptor: Codable {
    var provider: ChoiceProviderID
    var identifier: String
    var files: [URL]
    var configuration: Data
}

struct ContextMenu: Codable {
    var items: [String]
}

struct SettingsGroup: Codable {
    var id: GroupID
    var items: [SettingsItem]
    var localizedName: String
    var disposability: Disposability
    var sortOrder: Int
    var sortID: GroupSortID?
    var allChoiceID: ChoiceID?
    var shouldHideItemLabels: Bool?
    var contextMenu: ContextMenu?
    var thumbnail: Data?
}

struct SettingsItem: Codable {
    var id: ChoiceID
    var localizedName: String
    var thumbnail: ItemPicture
    var choice: ChoiceDescriptor
    var contentBadge: ContentBadge
    var showInTopLevel: Bool
    var sortOrder: Int
    var disposability: Disposability
    var contextMenu: ContextMenu?
}

struct ChoiceDescriptor: Codable {
    var id: ChoiceID
    var provider: ChoiceProviderID
    var identifier: String
    var name: String?
    var localizedDescription: String
    var thumbnail: ItemPicture
    var isDownloaded: Bool
    var options: [String]
}

/// Encoded as a bare string, as the private type is.
struct ChoiceProviderID: Codable {
    var rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Swift encodes an enum case without a payload as `{"caseName": {}}`; the
/// shims of such enums must too.
protocol CaseOnlyShim: Codable, RawRepresentable where RawValue == String {}

extension CaseOnlyShim {
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: AnyKey.self)
        guard let key = container.allKeys.first, let value = Self(rawValue: key.stringValue) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "unknown case"))
        }
        self = value
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: AnyKey.self)
        _ = container.nestedContainer(keyedBy: AnyKey.self, forKey: AnyKey(rawValue))
    }
}

enum Disposability: String, CaseOnlyShim {
    case none, removable, purgeable
}

enum ContentBadge: String, CaseOnlyShim {
    case none, video, dynamic
}

enum RefreshPolicy: String, CaseOnlyShim {
    case `default`
}

/// The private `Thumbnail` enum's `image(url:)` case: the tile's picture.
enum ItemPicture: Codable {
    case image(url: URL)

    private enum Keys: String, CodingKey { case image }
    private enum ImageKeys: String, CodingKey { case url }

    init(from decoder: any Decoder) throws {
        let nested = try decoder.container(keyedBy: Keys.self).nestedContainer(keyedBy: ImageKeys.self, forKey: .image)
        self = .image(url: try nested.decode(URL.self, forKey: .url))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Keys.self)
        var nested = container.nestedContainer(keyedBy: ImageKeys.self, forKey: .image)
        if case let .image(url) = self { try nested.encode(url, forKey: .url) }
    }
}

struct AnyKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(_ string: String) {
        stringValue = string
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) { nil }
}
