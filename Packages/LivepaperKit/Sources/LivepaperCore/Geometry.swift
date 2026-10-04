// Core's own geometry, so that it does not import CoreGraphics. y grows
// downwards, as it does in the picture and in SwiftUI; a host whose layers
// grow upwards flips once, at its edge.

public struct Point: Codable, Equatable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

public struct Size: Equatable, Sendable {
    public var width: Double
    public var height: Double

    public init(width: Double, height: Double) {
        self.width = width
        self.height = height
    }
}

public struct Rect: Equatable, Sendable {
    public var origin: Point
    public var size: Size

    public init(origin: Point, size: Size) {
        self.origin = origin
        self.size = size
    }

    public var maxX: Double { origin.x + size.width }
    public var maxY: Double { origin.y + size.height }
}
