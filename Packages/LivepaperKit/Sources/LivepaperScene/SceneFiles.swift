import Foundation

/// A scene wallpaper's own files, as its folder in the library keeps them
/// (`SceneFolder`): the item's `project.json`, and the package its project
/// names, which holds everything the scene is drawn from. Nothing outside the
/// package is read for drawing, so a name in the scene cannot lead out of it.
public struct SceneFiles: Sendable {
    public let folder: URL
    /// The scene's JSON inside the package, from the project's `file`.
    public let sceneFile: String
    let package: ScenePackage
    /// Values as the scene reads them, its user properties at the item's defaults.
    let values: SceneValues

    public init(folder: URL) throws {
        self.folder = folder
        let project = (try? sceneJSON(Data(contentsOf: folder.appending(path: SceneFolder.project, directoryHint: .notDirectory)))) ?? [:]
        sceneFile = project["file"] as? String ?? "scene.json"
        let packageFile = folder.appending(path: SceneFolder.package(for: sceneFile), directoryHint: .notDirectory)
        package = try ScenePackage(contentsOf: packageFile)
        values = SceneValues(project: project)
    }

    /// For tests: a package in memory, with the project's user properties.
    init(package: ScenePackage, sceneFile: String = "scene.json", project: [String: Any] = [:]) {
        folder = URL(filePath: "/", directoryHint: .isDirectory)
        self.sceneFile = sceneFile
        self.package = package
        values = SceneValues(project: project)
    }

    public func data(_ path: String) -> Data? {
        package.entry(path)
    }

    public func contains(_ path: String) -> Bool {
        package.entry(path) != nil
    }

    /// A JSON object from the package, byte-order mark or not.
    public func json(_ path: String) throws(SceneReadError) -> [String: Any] {
        try sceneJSON(package.require(path))
    }

    /// A file's text, or nil when the package has no such file. Bytes that are
    /// not UTF-8 read as U+FFFD, so a stray one does not lose the whole file.
    public func text(_ path: String) -> String? {
        data(path).map { String(forgivingUTF8: $0) }
    }

    /// `masks/foo` is `materials/masks/foo.tex`.
    public static func texturePath(_ name: String) -> String {
        "materials/\(name).tex"
    }

    /// The item's own source of a shader stage (`shaders/<name>.vert` or `.frag`), when the package carries one.
    public func shaderSource(_ name: String, stage: String) -> String? {
        text("shaders/\(name).\(stage)")
    }
}
