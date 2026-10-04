/// The app's side of the render host and the sensors that feed it.
///
/// `ExtensionHostClient` is the one `RenderHost`: it writes `render-state.json`,
/// posts the Darwin notifications, reads the extension's heartbeat into a
/// status, and restarts WallpaperAgent when the host asks for it or goes quiet,
/// never more than once in ten minutes, and never when the store names
/// Livepaper nowhere, since then quiet is all there is. The sensors (displays, power, lock,
/// sleep and wake, display sleep, covered displays) are `AsyncStream`s behind
/// small protocols; `ConditionsSensing` folds them into the `SensedConditions`
/// that the next render state carries.
///
/// The doors to macOS are here too. `WallpaperStore` and `Selection`
/// select Livepaper as the system wallpaper by editing the store, and put the
/// previous wallpaper back when the user leaves. `LoginItem` is
/// `SMAppService.mainApp`, `Hotkeys` Carbon's `RegisterEventHotKey`.
/// `RotationDriver` moves playlists on from one timer, on wake and once a
/// session (`SessionStart`). `CommandServer` answers the `livepaper` tool on a
/// socket, and `DiagnosticsReport` with `ExtensionLogLines` makes the report
/// Settings copies. Nothing here needs a permission.
public enum LivepaperSystem {
    /// The unified log subsystem of the app's own lines: the app's bundle identifier.
    public static let logSubsystem = "app.livepaper.Livepaper"
}
