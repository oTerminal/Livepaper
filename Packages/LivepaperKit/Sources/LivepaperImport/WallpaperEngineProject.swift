import Foundation

public enum WallpaperEngineProjectError: Error, Equatable, Sendable {
    /// Not a `project.json` anyone could read.
    case malformed
    /// A web page or an application: it runs code of its own, all the time,
    /// and Livepaper imports video and scene items only.
    case runsCode(String)
    /// A type Livepaper does not know.
    case unsupportedType(String)
    case noFile
    /// The project names a file outside its own folder. The name is kept as the project wrote it.
    case escapesFolder(String)
}

/// The two kinds of Wallpaper Engine item Livepaper imports.
public enum WallpaperEngineItemKind: String, Equatable, Sendable {
    /// A plain video file beside the project.
    case video
    /// A scene: its JSON, inside a package named after it, drawn live.
    case scene
}

/// What a Wallpaper Engine item's `project.json` says, with its paths known
/// to stay inside the item's folder.
///
/// The check is of the names only. Discovery resolves the real file and asks
/// again, which is what rules out a symlink.
public struct WallpaperEngineProject: Equatable, Sendable {
    public let kind: WallpaperEngineItemKind
    public let title: String?
    /// Relative to the item's folder, with `/` between the steps: the video
    /// file, or for a scene its JSON (`scene.json`), which is inside its package.
    public let file: String
    public let preview: String?

    /// Checks the paths as `parse` does: there is no way to a project whose file leads out of its folder.
    public init(
        kind: WallpaperEngineItemKind = .video, title: String?, file: String, preview: String?
    ) throws(WallpaperEngineProjectError) {
        guard !file.isEmpty else { throw .noFile }
        guard let contained = Self.containedPath(file) else { throw .escapesFolder(file) }
        self.kind = kind
        self.title = title
        self.file = contained
        self.preview = preview.flatMap(Self.containedPath)
    }

    public static func parse(_ data: Data) throws(WallpaperEngineProjectError) -> WallpaperEngineProject {
        guard
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let type = (object["type"] as? String)?.lowercased()
        else { throw .malformed }

        let kind: WallpaperEngineItemKind
        switch type {
        case "video": kind = .video
        case "scene": kind = .scene
        case "web", "application": throw .runsCode(type)
        default: throw .unsupportedType(type)
        }
        let title = (object["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        // The preview is a nicety. A bad one is dropped by the initialiser, it does not cost the user the wallpaper.
        return try WallpaperEngineProject(
            kind: kind,
            title: title?.isEmpty == false ? title : nil,
            file: object["file"] as? String ?? "",
            preview: object["preview"] as? String
        )
    }

    /// The path with `/` between its steps, or nil when any step could lead
    /// out of the folder. Wallpaper Engine is a Windows program, so `\` and
    /// drive letters are read the way Windows would.
    private static func containedPath(_ path: String) -> String? {
        let steps = path.replacing("\\", with: "/").split(separator: "/", omittingEmptySubsequences: false)
        guard let first = steps.first, !first.isEmpty, first != "~", !first.contains(":") else { return nil }
        guard steps.allSatisfy({ !$0.isEmpty && $0 != ".." && $0 != "." }) else { return nil }
        return steps.joined(separator: "/")
    }
}
