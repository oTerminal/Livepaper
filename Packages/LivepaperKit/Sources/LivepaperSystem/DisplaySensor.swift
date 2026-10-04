import AppKit
import CoreGraphics
import LivepaperCore

/// A display that is connected now.
nonisolated public struct ConnectedDisplay: Equatable, Sendable {
    public var identity: DisplayIdentity
    /// CoreGraphics' number for the display. It can change across a replug or a
    /// reboot, so nothing is keyed by it; `identity` is what lasts.
    public var displayID: UInt32
    /// The size of the current mode, in pixels.
    public var pixelSize: Size
    /// Where the display sits in global display space, in points, y growing
    /// downwards: the space the window list uses.
    public var frame: Rect
    /// The height of the strip beside the camera housing at the top of the
    /// display, in points: `NSScreen.safeAreaInsets.top`, 0 on a display with
    /// no housing. No window covers that strip, not even a fullscreen one.
    public var topSafeAreaInset: Double

    public init(identity: DisplayIdentity, displayID: UInt32, pixelSize: Size, frame: Rect, topSafeAreaInset: Double = 0) {
        self.identity = identity
        self.displayID = displayID
        self.pixelSize = pixelSize
        self.frame = frame
        self.topSafeAreaInset = topSafeAreaInset
    }
}

/// The connected displays.
public protocol DisplaySensor: AnyObject {
    /// The connected displays now, and again each time they change.
    func updates() -> AsyncStream<[ConnectedDisplay]>
}

/// Reads the displays from CoreGraphics, again once a reconfiguration has settled.
public final class SystemDisplaySensor: DisplaySensor {
    /// A replug or a mode change arrives as several notifications; the displays
    /// are read once they have been quiet for this long.
    public static let settle: Duration = .milliseconds(500)

    private let broadcast = Broadcast<[ConnectedDisplay]>()
    private var observer: (any NSObjectProtocol)?
    private var settling: Task<Void, Never>?

    public init() {
        broadcast.whenRead(start: { [weak self] in self?.start() }, stop: { [weak self] in self?.stop() })
    }

    public func updates() -> AsyncStream<[ConnectedDisplay]> {
        broadcast.stream()
    }

    private func start() {
        observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reconfigured() }
        }
        broadcast.send(ConnectedDisplays.current())
    }

    private func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        settling?.cancel()
        settling = nil
    }

    private func reconfigured() {
        settling?.cancel()
        settling = broadcast.sendSettled(after: [Self.settle]) { ConnectedDisplays.current() }
    }
}

/// The displays CoreGraphics lists as online, asleep ones included, and not
/// the ones that mirror another: those show the other display's picture.
enum ConnectedDisplays {
    static func current() -> [ConnectedDisplay] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        let insets = topSafeAreaInsets()
        return ids.prefix(Int(count)).compactMap { display(for: $0, topSafeAreaInset: insets[$0] ?? 0) }
    }

    static func display(for id: CGDirectDisplayID, topSafeAreaInset: Double) -> ConnectedDisplay? {
        guard CGDisplayMirrorsDisplay(id) == kCGNullDirectDisplay,
              let cfUUID = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
              let uuid = UUID(uuidString: CFUUIDCreateString(nil, cfUUID) as String)
        else { return nil }
        let bounds = CGDisplayBounds(id)
        let mode = CGDisplayCopyDisplayMode(id)
        return ConnectedDisplay(
            identity: DisplayIdentity(uuid: uuid),
            displayID: id,
            pixelSize: Size(
                width: Double(mode?.pixelWidth ?? CGDisplayPixelsWide(id)),
                height: Double(mode?.pixelHeight ?? CGDisplayPixelsHigh(id))
            ),
            frame: Rect(bounds),
            topSafeAreaInset: topSafeAreaInset
        )
    }

    /// Each screen's top safe-area inset, by its CoreGraphics number. Only a
    /// display with a camera housing has one; a display AppKit lists no
    /// screen for is taken to have none.
    static func topSafeAreaInsets() -> [CGDirectDisplayID: Double] {
        let screenNumber = NSDeviceDescriptionKey("NSScreenNumber")
        return Dictionary(
            NSScreen.screens.compactMap { screen in
                (screen.deviceDescription[screenNumber] as? NSNumber).map { ($0.uint32Value, Double(screen.safeAreaInsets.top)) }
            },
            uniquingKeysWith: { first, _ in first }
        )
    }
}

extension Rect {
    nonisolated init(_ rect: CGRect) {
        self.init(
            origin: Point(x: Double(rect.origin.x), y: Double(rect.origin.y)),
            size: Size(width: Double(rect.size.width), height: Double(rect.size.height))
        )
    }
}
