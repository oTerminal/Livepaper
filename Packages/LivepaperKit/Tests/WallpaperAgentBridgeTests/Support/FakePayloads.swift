import CoreGraphics
import Foundation

// Stand-ins for WallpaperExtensionKit's XPC payloads: Swift structs boxed in
// NSObject subclasses, with the labels, nesting and field types that the
// framework's type metadata lists on macOS 27.0. Only the labels matter to the
// bridge; the type names are free.

struct FakeXPCBox<Value> {
    var rawValue: Value
}

struct FakeWallpaperID {
    var id: UUID
}

/// `WallpaperIDXPC`: `box.rawValue.id`.
final class FakeIDXPC: NSObject {
    let box: FakeXPCBox<FakeWallpaperID>

    init(_ id: UUID) {
        box = FakeXPCBox(rawValue: FakeWallpaperID(id: id))
    }
}

/// An identifier from a macOS that no longer carries a UUID.
final class FakeNamedIDXPC: NSObject {
    let box: FakeXPCBox<String>

    init(_ name: String) {
        box = FakeXPCBox(rawValue: name)
    }
}

/// The agent's `WallpaperPresentationMode`, which its requests carry as `presentationMode`.
enum FakeAgentSurfaceMode {
    case `default`, locked, idle
    /// A mode this bridge has not seen.
    case ambient
    /// A mode with a payload, as a later macOS might add.
    case dimmed(level: Double)
}

enum FakeActivityState {
    case active, suspended
    /// A state this bridge has not seen.
    case dozing
}

enum FakeSystemAppearance {
    case light, dark
}

struct FakeDestination {
    var size: CGSize
    var colorSpace: CGColorSpace
    var scaleFactor: CGFloat
    var directDisplayID: UInt32?

    init(width: Double, height: Double, scale: Double, display: UInt32?) {
        size = CGSize(width: width, height: height)
        colorSpace = CGColorSpaceCreateDeviceRGB()
        scaleFactor = scale
        directDisplayID = display
    }
}

struct FakeDescriptor {
    var files: [URL] = []
    var configuration = Data("livepaper".utf8)
    var optionValues: [String: String]?
}

struct FakeCreationRequest {
    var descriptor = FakeDescriptor()
    var cacheDirectory: URL?
    var destination: FakeDestination
    var isPreview: Bool
    var presentationMode: FakeAgentSurfaceMode = .default
    var activityState: FakeActivityState = .active
    var systemAppearance: FakeSystemAppearance = .dark
    var debugBackgrounds = false
}

/// `WallpaperCreationRequestXPC`: the struct straight in `rawValue`.
final class FakeCreationRequestXPC: NSObject {
    let rawValue: FakeCreationRequest

    init(_ request: FakeCreationRequest) {
        rawValue = request
    }
}

struct FakeUpdateRequest {
    var presentationMode: FakeAgentSurfaceMode
    var activityState: FakeActivityState = .active
    var systemAppearance: FakeSystemAppearance = .dark
    var destination: FakeDestination
    var debugBackgrounds = false
}

/// `WallpaperUpdateRequestXPC`: the struct in `box.rawValue`.
final class FakeUpdateRequestXPC: NSObject {
    let box: FakeXPCBox<FakeUpdateRequest>

    init(_ request: FakeUpdateRequest) {
        box = FakeXPCBox(rawValue: request)
    }
}

struct FakeBareRequest {
    var descriptor = FakeDescriptor()
}

/// A request from a macOS that moved or dropped every field the bridge reads.
final class FakeBareRequestXPC: NSObject {
    let rawValue = FakeBareRequest()
}

struct FakeDestinationWithoutDisplay {
    var size: CGSize
    var scaleFactor: CGFloat
}

struct FakeSparseRequest {
    var destination: FakeDestinationWithoutDisplay
}

/// A request whose destination has a size and a scale, and nothing else.
final class FakeSparseRequestXPC: NSObject {
    let rawValue: FakeSparseRequest

    init(width: Double, height: Double, scale: Double) {
        let destination = FakeDestinationWithoutDisplay(size: CGSize(width: width, height: height), scaleFactor: scale)
        rawValue = FakeSparseRequest(destination: destination)
    }
}

/// A payload built fresh for each row: the fakes are not `Sendable`, rows are.
struct Payload: Sendable {
    let make: @Sendable () -> Any?

    init(_ make: @escaping @Sendable () -> Any?) {
        self.make = make
    }

    static let none = Payload { nil }
}
