import AppKit
import CoreGraphics
import LivepaperCore

/// Which connected displays are fully covered by a window.
public protocol CoveredDisplaySensor: AnyObject {
    /// The covered displays now, and again each time that changes.
    func updates() -> AsyncStream<Set<DisplayIdentity>>
    /// Whether a covered display pauses the wallpaper: the "Desktop fully
    /// covered" rule, which `ConditionsSensing` passes on. While it does, a
    /// covered display is looked at every second until it is uncovered.
    var coveringPauses: Bool { get set }
}

/// Reads the window list when something happens that can cover or uncover a
/// display, and every second while a covered display pauses the wallpaper or
/// Show Desktop has the windows aside (`CoveredDisplayReader`). No
/// notification says that a window moved, so a window dragged or resized over
/// a whole display by hand is seen at the next of these events; covering a
/// display that way is rare, and a fullscreen app, the usual case, changes
/// the Space. Uncovering is not left to the next event: Show Desktop, from a
/// hot corner, moves the windows aside and back and posts nothing (found
/// on screen).
///
/// What it reads again on:
/// - an app activated, launched, quit, hidden or shown: the front window changed;
/// - the active Space changed: entering or leaving fullscreen is a Space change;
/// - the displays were reconfigured: the frames being covered changed;
/// - the Mac or its screens woke, the session became active again, or the
///   screen was unlocked: what is on screen then may not be what was before.
public final class SystemCoveredDisplaySensor: CoveredDisplaySensor {
    public var coveringPauses: Bool {
        get { reader.coveringPauses }
        set { reader.coveringPauses = newValue }
    }

    private let broadcast: Broadcast<Set<DisplayIdentity>>
    private let reader: CoveredDisplayReader<ContinuousClock>
    private let triggers = NotificationTriggers()

    public init() {
        let broadcast = Broadcast<Set<DisplayIdentity>>()
        self.broadcast = broadcast
        reader = CoveredDisplayReader(clock: ContinuousClock(), read: { WindowList.reading() }, report: broadcast.send)
        broadcast.whenRead(start: { [weak self] in self?.start() }, stop: { [weak self] in self?.stop() })
    }

    public func updates() -> AsyncStream<Set<DisplayIdentity>> {
        broadcast.stream()
    }

    private func start() {
        let triggerList: [NotificationTriggers.Trigger] = [
            .workspace(NSWorkspace.didActivateApplicationNotification),
            .workspace(NSWorkspace.didLaunchApplicationNotification),
            .workspace(NSWorkspace.didTerminateApplicationNotification),
            .workspace(NSWorkspace.didHideApplicationNotification),
            .workspace(NSWorkspace.didUnhideApplicationNotification),
            .workspace(NSWorkspace.activeSpaceDidChangeNotification),
            .workspace(NSWorkspace.didWakeNotification),
            .workspace(NSWorkspace.screensDidWakeNotification),
            .workspace(NSWorkspace.sessionDidBecomeActiveNotification),
            .application(NSApplication.didChangeScreenParametersNotification),
            .distributed(SystemLockSensor.unlocked),
        ]
        triggers.start(triggerList) { [weak self] _ in self?.reader.somethingMoved() }
        reader.start()
    }

    private func stop() {
        triggers.stop()
        reader.stop()
    }
}

/// The on-screen windows, by bounds, layer and owner. Window names would need
/// Screen Recording, so they are never asked for.
enum WindowList {
    /// WindowManager, whose window over the whole display means Show Desktop.
    static let windowManager = "com.apple.WindowManager"

    /// The Dock, whose display-sized window sits above the normal level on
    /// every display, loginwindow, whose lock screen shield stays in the
    /// list for about a second after unlocking, and WindowManager, whose Show
    /// Desktop window the desktop shows through.
    static let bundleIdentifiersThatCoverNothing = ["com.apple.dock", "com.apple.loginwindow", windowManager]

    /// What the list says now, the owners found on each read, since the Dock
    /// gets a new process when it restarts.
    static func reading() -> WindowListReading {
        let windows = onScreen()
        let displays = ConnectedDisplays.current()
        return WindowListReading(
            covered: coveredDisplays(windows: windows, displays: displays, ignoringOwners: ownersThatCoverNothing()),
            showingDesktop: isShowingDesktop(windows: windows, displays: displays, windowManager: processes(of: [windowManager]))
        )
    }

    /// The app itself and `bundleIdentifiersThatCoverNothing`.
    static func ownersThatCoverNothing() -> Set<Int32> {
        processes(of: bundleIdentifiersThatCoverNothing).union([ProcessInfo.processInfo.processIdentifier])
    }

    static func processes(of bundleIdentifiers: [String]) -> Set<Int32> {
        Set(bundleIdentifiers.flatMap(NSRunningApplication.runningApplications(withBundleIdentifier:)).map(\.processIdentifier))
    }

    static func onScreen() -> [WindowListEntry] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return [] }
        return windows.compactMap { window in
            guard let boundsDictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDictionary),
                  let layer = window[kCGWindowLayer as String] as? NSNumber,
                  let owner = window[kCGWindowOwnerPID as String] as? NSNumber
            else { return nil }
            return WindowListEntry(bounds: Rect(bounds), layer: layer.intValue, ownerPID: owner.int32Value)
        }
    }
}
