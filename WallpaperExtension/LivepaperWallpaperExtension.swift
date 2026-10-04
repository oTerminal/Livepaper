import ExtensionFoundation
import Foundation
import LivepaperCore
import LivepaperPlayback
import WallpaperAgentBridge

/// The render host: WallpaperAgent launches this extension, asks
/// it for a remote context per surface, and shows that on the desktop, the
/// lock screen and the System Settings preview. What each surface shows comes
/// from the render state the app last wrote; the extension reads the library,
/// writes nothing, and tells the app how it is by its heartbeat alone.
@main
final class LivepaperWallpaperExtension: AppExtension {
    private let listener: WallpaperAgentListener
    private let beacon: HeartbeatBeacon
    private let notifications: AppNotifications
    private let systemEvents: SystemEvents
    private let reconfiguration: DisplayReconfiguration

    init() {
        let bundle = Bundle.main
        ExtensionLog.notice(.launched(
            pid: getpid(),
            version: bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "none",
            build: bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "none",
            bundle: bundle.bundlePath
        ))
        // First, before any connection is accepted: the listener allows the
        // payload classes the check found.
        let check = WallpaperAgentBridge.load()
        let location = RealHome.libraryLocation()

        let hosted = HostedSurfaces()
        let supervisor = PlaybackSupervisor(
            location: location,
            clock: ContinuousClock(),
            now: { Date() },
            logger: .supervisor,
            tearDown: { hosted.tearDown($0) }
        )
        let requests = AgentRequests(hosted: hosted, supervisor: supervisor)
        // One listener for every connection: it owns the spiral detector.
        listener = WallpaperAgentListener(
            handler: requests,
            settings: SettingsEntry(provider: WallpaperExtensionIdentity.bundleIdentifier, tile: Self.settingsTile(in: bundle)),
            neutralColour: SurfaceLayers.neutralColour
        )
        beacon = HeartbeatBeacon(supervisor: supervisor, listener: listener, selfCheckFailed: !check.isUsable)
        requests.beacon = beacon
        notifications = AppNotifications(
            reader: RenderStateReader(location: location), supervisor: supervisor, hosted: hosted, beacon: beacon
        )
        systemEvents = SystemEvents(supervisor: supervisor)
        reconfiguration = DisplayReconfiguration(hosted: hosted, supervisor: supervisor)

        notifications.start()
        systemEvents.start()
        reconfiguration.start()
        beacon.start()
    }

    var configuration: some AppExtensionConfiguration { AgentConnections(listener: listener) }

    /// Livepaper's tile in System Settings > Wallpaper, which WallpaperAgent
    /// reads from the extension's bundle.
    private static func settingsTile(in bundle: Bundle) -> URL {
        if let tile = bundle.url(forResource: "SettingsTile", withExtension: "png") { return tile }
        ExtensionLog.error(.noSettingsTile)
        return bundle.bundleURL.appending(path: "Contents/Resources/SettingsTile.png", directoryHint: .notDirectory)
    }
}

/// Hands every connection WallpaperAgent makes to the one listener. Not named
/// `Configuration`, which is `AppExtension`'s associated type, and nonisolated
/// because `accept` is called off the main actor.
nonisolated struct AgentConnections: AppExtensionConfiguration {
    let listener: WallpaperAgentListener

    func accept(connection: NSXPCConnection) -> Bool {
        listener.accept(connection)
    }
}
