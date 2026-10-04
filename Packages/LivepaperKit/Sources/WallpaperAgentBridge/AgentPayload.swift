// Request field extraction by Mirror, adapted from Phosphene's
// WallpaperXPCHandler.swift (MIT, (c) 2026 kageroumado,
// https://github.com/kageroumado/phosphene); see NOTICE at the repository root.

import CoreGraphics
import Foundation
import LivepaperCore

/// Reads WallpaperAgent's XPC payloads, which are Swift structs boxed in NSObject
/// subclasses: only reflection reaches their fields. A field is found by its
/// label, nearest the top first, wherever the box keeps it, so that one
/// payload's `rawValue.isPreview` and another's `box.rawValue.presentationMode`
/// read alike. On macOS 27.0 the labels are `destination` (`size`, `scaleFactor`,
/// `directDisplayID`), `isPreview`, `presentationMode` and `activityState`, and
/// the identifier is `box.rawValue.id`.
enum AgentPayload {
    static func surface(in id: Any?) -> UUID? {
        guard let id else { return nil }
        if let uuid = id as? UUID { return uuid }
        var found: UUID?
        breadthFirst(from: id) { _, value in
            found = value as? UUID
            return found != nil
        }
        return found
    }

    static func acquire(_ request: Any?, surface: UUID) -> AcquireRequest {
        AcquireRequest(
            surface: surface,
            destination: destination(in: request),
            isPreview: field("isPreview", in: request).flatMap { $0 as? Bool } ?? false,
            mode: field("presentationMode", in: request).map { AgentSurfaceMode(agentName: caseName(of: $0)) },
            activityState: field("activityState", in: request).map { ActivityState(agentName: caseName(of: $0)) }
        )
    }

    static func update(_ request: Any?, surface: UUID?) -> UpdateRequest {
        UpdateRequest(
            surface: surface,
            destination: destination(in: request),
            mode: field("presentationMode", in: request).map { AgentSurfaceMode(agentName: caseName(of: $0)) },
            activityState: field("activityState", in: request).map { ActivityState(agentName: caseName(of: $0)) }
        )
    }

    static func destination(in request: Any?) -> SurfaceDestination {
        let destination = field("destination", in: request)
        let size = field("size", in: destination).flatMap { $0 as? CGSize }
        return SurfaceDestination(
            display: field("directDisplayID", in: destination).flatMap(displayID),
            size: size.map { Size(width: Double($0.width), height: Double($0.height)) },
            scale: field("scaleFactor", in: destination).flatMap(real)
        )
    }

    // The deepest a field is looked for, and how many values are looked at in
    // all, so that a payload grown large costs a bounded search.
    private static let maximumDepth = 8
    private static let maximumValues = 512

    /// The value labelled `label` nearest the top of `value`, unwrapped from any
    /// optional; `nil` when there is none or it is an empty optional.
    static func field(_ label: String, in value: Any?) -> Any? {
        guard let value else { return nil }
        var found: Any?
        breadthFirst(from: value) { childLabel, child in
            guard childLabel == label else { return false }
            found = child
            return true
        }
        return found.flatMap(unwrapped)
    }

    /// Visits the values under `root`, nearest the top first, until `visit`
    /// returns true.
    private static func breadthFirst(from root: Any, _ visit: (String?, Any) -> Bool) {
        var level = [root]
        var looked = 0
        for _ in 0..<maximumDepth {
            var next: [Any] = []
            for value in level {
                for child in Mirror(reflecting: value).children {
                    if visit(child.label, child.value) { return }
                    looked += 1
                    guard looked < maximumValues else { return }
                    next.append(child.value)
                }
            }
            guard !next.isEmpty else { return }
            level = next
        }
    }

    private static func unwrapped(_ value: Any) -> Any? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return value }
        return mirror.children.first.flatMap { unwrapped($0.value) }
    }

    /// The name of an enum's case, with or without a payload.
    static func caseName(of value: Any) -> String {
        let mirror = Mirror(reflecting: value)
        if mirror.displayStyle == .enum, let label = mirror.children.first?.label { return label }
        return String(describing: value)
    }

    private static func real(_ value: Any) -> Double? {
        switch value {
        case let number as CGFloat: Double(number)
        case let number as Double: number
        case let number as Float: Double(number)
        case let number as Int: Double(number)
        default: nil
        }
    }

    private static func displayID(_ value: Any) -> UInt32? {
        switch value {
        case let number as UInt32: number
        case let number as Int: UInt32(exactly: number)
        case let number as UInt: UInt32(exactly: number)
        default: nil
        }
    }
}
