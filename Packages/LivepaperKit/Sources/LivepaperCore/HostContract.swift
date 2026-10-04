/// What the app and the wallpaper extension agree on: the extension's
/// identity, where it logs, and the Darwin notifications between them.
/// Each value is chosen once and never changes: the
/// wallpaper store keys the user's selection by the bundle identifier, and
/// other tools read the log by its subsystem.
public enum WallpaperExtensionIdentity {
    /// The extension's bundle identifier, which the wallpaper store keys the user's selection by.
    public static let bundleIdentifier = "app.livepaper.Livepaper.WallpaperExtension"
    /// The one choice the extension offers, and the configuration it carries.
    public static let choiceIdentifier = "livepaper"
    /// The unified log subsystem of the extension's own lines.
    public static let logSubsystem = "app.livepaper.extension"
}

/// The Darwin notifications between the app and the extension. The app never
/// talks to the extension any other way; the extension never writes a file.
public enum HostNotification {
    /// App to extension: `render-state.json` was replaced.
    public static let renderStateChanged = DarwinNotification("app.livepaper.render-state")
    /// Extension to app: its state is a packed `Heartbeat`.
    public static let heartbeat = DarwinNotification("app.livepaper.heartbeat")
    /// App to extension: its state is the raw value of the `RecoveryLevel` to
    /// try inside the process. `.restartAgent` is the app's own and never sent.
    public static let recover = DarwinNotification("app.livepaper.recover")
    /// App to extension: run the watchdog's check now.
    public static let check = DarwinNotification("app.livepaper.check")
    /// App to extension: state 1 switches the playback-metrics probe on, 0 off.
    /// The extension also reads the state when it launches.
    public static let playbackMetrics = DarwinNotification("app.livepaper.playback-metrics")
}
