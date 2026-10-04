import Foundation
import LivepaperScene

/// The wording of the engine's and the layer tree's own log lines, in one place. The metrics
/// line, which other tools read, is `PlaybackMetrics.logLine(for:)`.
enum EngineLog {
    /// A library video as the log names it: its folder, which is the wallpaper's ID, and its file.
    static func name(of url: URL?) -> String {
        guard let url else { return "nothing" }
        return "\(url.deletingLastPathComponent().lastPathComponent)/\(url.lastPathComponent)"
    }

    static func cannotRead(_ url: URL, _ error: any Error) -> String {
        "engine: cannot read \(name(of: url)): \(describe(error))"
    }

    static func rendererFailed(_ url: URL?, _ error: (any Error)?) -> String {
        "engine: renderer failed on \(name(of: url)), starting again from a fresh reader: \(describe(error))"
    }

    static func rendererAskedForFlush(_ url: URL?) -> String {
        "engine: renderer asked for a flush on \(name(of: url)), starting again from a fresh reader"
    }

    static func readerFailed(_ url: URL?, _ error: (any Error)?) -> String {
        "engine: reader failed on \(name(of: url)), starting again from a fresh reader: \(describe(error))"
    }

    static func passWithoutFrames(_ url: URL?) -> String {
        "engine: a pass of \(name(of: url)) had no frames"
    }

    static func audioFailed(_ url: URL?, _ error: (any Error)?) -> String {
        "engine: audio failed on \(name(of: url)), going on without it: \(describe(error))"
    }

    static func gaveUp(_ url: URL?, restarts: Int) -> String {
        "engine: gave up on \(name(of: url)) after \(restarts) restarts without a loop"
    }

    static func cannotPlay(_ surface: SurfaceID, _ url: URL) -> String {
        "layers: surface \(surface) cannot play \(name(of: url)), holding its poster"
    }

    static func posterUnreadable(_ surface: SurfaceID, _ url: URL) -> String {
        "layers: surface \(surface) cannot read the poster \(name(of: url)), showing the neutral colour"
    }

    static func notReadyForDisplay(_ surface: SurfaceID, _ url: URL?) -> String {
        "layers: surface \(surface) had no picture of \(name(of: url)) after 1 s, going ahead"
    }

    // MARK: Scenes

    static func noMetalDevice(_ surface: SurfaceID) -> String {
        "scene: surface \(surface) has no Metal device, holding the poster"
    }

    /// A scene is named by its folder, which is the wallpaper's ID.
    static func sceneLoaded(_ surface: SurfaceID, _ folder: URL, by type: any SceneDrawing.Type, milliseconds: Double) -> String {
        "scene: surface \(surface) loaded \(folder.lastPathComponent) in \(Int(milliseconds.rounded())) ms, drawn by \(type)"
    }

    /// What of the scene is not drawn as it asks, once, after it loads.
    static func sceneNotes(_ surface: SurfaceID, _ folder: URL, _ notes: [String]) -> String {
        "scene: surface \(surface) draws \(folder.lastPathComponent) without: \(notes.joined(separator: "; "))"
    }

    static func sceneCannotLoad(_ surface: SurfaceID, _ folder: URL, _ error: any Error) -> String {
        "scene: surface \(surface) cannot load \(folder.lastPathComponent), holding the poster: \(describe(error))"
    }

    static func sceneDrawing(_ surface: SurfaceID, from time: Double) -> String {
        "scene: surface \(surface) drawing at \(Int(LivepaperScene.framesPerSecond)) fps from \(String(format: "%.2f", time)) s"
    }

    static func sceneStopped(_ surface: SurfaceID, at time: Double, _ reason: String) -> String {
        "scene: surface \(surface) stopped drawing at \(String(format: "%.2f", time)) s (\(reason))"
    }

    static func sceneFirstPicture(_ surface: SurfaceID, milliseconds: Double) -> String {
        "scene: surface \(surface) first picture drawn \(Int(milliseconds.rounded())) ms after the start"
    }

    static func sceneShown(_ surface: SurfaceID, _ folder: URL, waited: Bool) -> String {
        "scene: surface \(surface) shows \(folder.lastPathComponent) in the Metal slot\(waited ? "" : ", with no picture after 1 s")"
    }

    /// A still of the scene up: its last picture stays in the slot, the scene let go and its poster under it.
    static func sceneHeldStill(_ surface: SurfaceID, _ folder: URL, at time: Double) -> String {
        "scene: surface \(surface) holds \(folder.lastPathComponent) still on its last picture, at \(String(format: "%.2f", time)) s"
    }

    private static func describe(_ error: (any Error)?) -> String {
        guard let error = error as NSError? else { return "no error given" }
        return "\(error.domain) \(error.code): \(error.localizedDescription)"
    }
}
