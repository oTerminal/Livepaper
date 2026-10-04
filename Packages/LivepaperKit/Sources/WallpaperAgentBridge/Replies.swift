// Remote-context and snapshot object construction adapted from Phosphene's
// RuntimeHelpers.swift and SnapshotCreation.swift (MIT, (c) 2026 kageroumado,
// https://github.com/kageroumado/phosphene); see NOTICE at the repository root.

import CoreGraphics
import Foundation
import IOSurface

/// The objects WallpaperAgent expects back. Their classes have no initialiser
/// that can be called from here, so each is made empty and its one ivar written,
/// where `ReplySlot` has checked that the value fits and nothing else is there.
enum AgentReplies {
    /// A `WallpaperRemoteContextXPC` holding the context ID; `nil` when the
    /// layout is not the expected one.
    static func remoteContext(_ id: RemoteContextID) -> AnyObject? {
        guard let object = EmptyReply(.remoteContext) else { return nil }
        object.slot.storeBytes(of: id.rawValue, as: UInt32.self)
        return object.value
    }

    /// A `WallpaperSnapshotXPC` holding the surface, which it keeps and releases
    /// when it goes; `nil` when the layout is not the expected one.
    static func snapshot(_ surface: IOSurface) -> AnyObject? {
        guard let object = EmptyReply(.snapshot) else { return nil }
        object.slot.storeBytes(of: Unmanaged.passRetained(surface).toOpaque(), as: UnsafeMutableRawPointer.self)
        return object.value
    }

    /// The size of a snapshot made of the neutral colour, when the extension has
    /// no picture for the surface. How the agent fits a snapshot to a display
    /// has not been watched, so this is the spike's size.
    static let fallbackPixels = (width: 1920, height: 1080)

    /// A surface filled with one colour, in sRGB and tagged so, so that it
    /// matches the same colour on a layer.
    static func solidSurface(_ colour: CGColor, width: Int, height: Int) -> IOSurface? {
        let properties: [IOSurfacePropertyKey: any Sendable] = [
            .width: width, .height: height, .bytesPerElement: 4,
            .pixelFormat: 0x4247_5241, // 'BGRA'
        ]
        guard let surface = IOSurface(properties: properties), let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        if let tag = space.copyPropertyList() { IOSurfaceSetValue(surface, kIOSurfaceColorSpace, tag) }
        surface.lock(options: [], seed: nil)
        defer { surface.unlock(options: [], seed: nil) }
        let context = CGContext(
            data: surface.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: surface.bytesPerRow,
            space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )
        guard let context else { return nil }
        context.setFillColor(colour)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return surface
    }
}

/// An object of a reply class, made without its initialiser, and where its one
/// value goes.
private struct EmptyReply {
    let value: AnyObject
    let slot: UnsafeMutableRawPointer

    init?(_ reply: ReplySlot) {
        guard let type = reply.type, let offset = reply.offset, let instance = class_createInstance(type, 0) else { return nil }
        value = instance as AnyObject
        slot = Unmanaged.passUnretained(value).toOpaque().advanced(by: offset)
    }
}
