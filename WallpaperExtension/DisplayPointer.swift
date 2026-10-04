import AppKit
import CoreGraphics
import Foundation
import LivepaperCore
import Synchronization

/// Where the pointer is over one display, for a scene that follows it (camera
/// parallax): 0 to 1 from the display's top left, clamped to it.
/// Read on the scene's render thread each frame. The window server gives the
/// pointer's place without a permission; `NSEvent.mouseLocation` is its AppKit
/// spelling, in the bottom-left coordinates AppKit uses.
nonisolated final class DisplayPointer: Sendable {
    private let display: DisplayIdentity
    /// The display's frame in AppKit's global coordinates, looked up again now and then, since displays move.
    private let frame = Mutex<(rect: CGRect, readAt: Int)?>(nil)
    private static let reported = Atomic(false)

    init(display: DisplayIdentity) {
        self.display = display
    }

    func position() -> SIMD2<Float>? {
        guard let rect = displayFrame() else { return nil }
        let location = NSEvent.mouseLocation
        Self.report(location, on: rect)
        guard rect.width > 0, rect.height > 0, location.x.isFinite, location.y.isFinite else { return nil }
        let x = (location.x - rect.minX) / rect.width
        let y = (rect.maxY - location.y) / rect.height
        return SIMD2(Float(min(max(x, 0), 1)), Float(min(max(y, 0), 1)))
    }

    private func displayFrame() -> CGRect? {
        frame.withLock { frame in
            if let known = frame, known.readAt < 300 {
                frame?.readAt += 1
                return known.rect
            }
            guard let id = Displays.display(with: display) else { return nil }
            // CoreGraphics' bounds are from the top left of the main display; AppKit's frames from its bottom left.
            let bounds = CGDisplayBounds(id)
            let mainHeight = CGDisplayBounds(CGMainDisplayID()).height
            let rect = CGRect(x: bounds.minX, y: mainHeight - bounds.maxY, width: bounds.width, height: bounds.height)
            frame = (rect, 0)
            return rect
        }
    }

    /// Once a process: whether the pointer could be read, for a check.
    private static func report(_ location: NSPoint, on rect: CGRect) {
        guard !reported.exchange(true, ordering: .relaxed) else { return }
        ExtensionLog.notice(.pointerRead(location, display: rect))
    }
}
