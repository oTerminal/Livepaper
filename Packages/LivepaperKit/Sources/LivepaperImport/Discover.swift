import Foundation
import LivepaperScene

/// A source file that an import can be started on.
public struct ImportCandidate: Equatable, Sendable {
    /// The file the import reads and fingerprints: a video file, or a scene's package.
    public let source: URL
    /// What the wallpaper will be called: the project's title for a Wallpaper
    /// Engine item, otherwise the file's name.
    public let name: String
    /// The Wallpaper Engine item's own preview image, to show while the import
    /// runs. A scene's poster and hover preview are made from it.
    public let preview: URL?
    /// Set for a Wallpaper Engine scene, whose package is `source`.
    public let scene: SceneItem?

    public init(source: URL, name: String, preview: URL? = nil, scene: SceneItem? = nil) {
        self.source = source
        self.name = name
        self.preview = preview
        self.scene = scene
    }
}

/// The rest of a Wallpaper Engine scene item, beside its package.
public struct SceneItem: Equatable, Sendable {
    /// The item's `project.json`, which the library keeps with the package.
    public let project: URL
    /// The scene's JSON, by its name inside the package: the project's `file`.
    public let sceneFile: String

    public init(project: URL, sceneFile: String) {
        self.project = project
        self.sceneFile = sceneFile
    }
}

/// Why something the user provided will not be imported, in a form the UI can put into words.
public enum SkipReason: Error, Equatable, Sendable {
    case wallpaperEngine(WallpaperEngineProjectError)
    /// The Wallpaper Engine project names a file that is not in its folder.
    case missingFile(String)
    /// A scene item whose folder has no package of this name: its files lie
    /// loose, which Livepaper does not read.
    case noScenePackage(String)
}

public struct SkippedSource: Equatable, Sendable {
    public let url: URL
    public let reason: SkipReason

    public init(url: URL, reason: SkipReason) {
        self.url = url
        self.reason = reason
    }
}

public struct Discovery: Equatable, Sendable {
    public var candidates: [ImportCandidate]
    public var skipped: [SkippedSource]

    public init(candidates: [ImportCandidate] = [], skipped: [SkippedSource] = []) {
        self.candidates = candidates
        self.skipped = skipped
    }
}

public enum DiscoverError: Error, Equatable, Sendable {
    case notFound(URL)
}

/// The extensions a folder is searched for. A file the user picks by itself is
/// taken whatever it is called, and the probe decides.
public let importableExtensions: Set<String> = ["mp4", "m4v", "mov", "webm", "mkv", "avi", "wmv", "gif"]

/// A file, a folder or a Wallpaper Engine folder, as the source files to import.
///
/// A folder with a `project.json` is a Wallpaper Engine item and gives one
/// candidate, or nothing: a video item its video file, a scene its package.
/// Any other folder gives the video files in it, and is
/// searched through.
public func discoverSources(at url: URL) throws -> Discovery {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
        throw DiscoverError.notFound(url)
    }
    guard isDirectory.boolValue else {
        return Discovery(candidates: [ImportCandidate(source: url, name: url.deletingPathExtension().lastPathComponent)])
    }
    var discovery = Discovery()
    try search(URL(filePath: url.path, directoryHint: .isDirectory), into: &discovery)
    return discovery
}

private func search(_ folder: URL, into discovery: inout Discovery) throws {
    let project = folder.appending(path: "project.json", directoryHint: .notDirectory)
    if let data = try? Data(contentsOf: project) {
        switch wallpaperEngineItem(in: folder, project: data) {
        case .success(let candidate): discovery.candidates.append(candidate)
        case .failure(let reason): discovery.skipped.append(SkippedSource(url: folder, reason: reason))
        }
        return
    }

    let contents = try FileManager.default.contentsOfDirectory(
        at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey], options: [.skipsHiddenFiles]
    )
    let byName = contents.sorted {
        $0.lastPathComponent.compare($1.lastPathComponent, options: [.caseInsensitive, .numeric]) == .orderedAscending
    }
    // Files first, then the folders, each in name order.
    var folders: [URL] = []
    for item in byName {
        let values = try item.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        if values.isDirectory == true {
            if values.isPackage != true { folders.append(item) }
        } else if importableExtensions.contains(item.pathExtension.lowercased()) {
            discovery.candidates.append(ImportCandidate(source: item, name: item.deletingPathExtension().lastPathComponent))
        }
    }
    for folder in folders {
        try search(folder, into: &discovery)
    }
}

private func wallpaperEngineItem(in folder: URL, project data: Data) -> Result<ImportCandidate, SkipReason> {
    // The project itself may be a link, and a scene's is copied into the library: it has to be the folder's own.
    let projectFile = folder.appending(path: SceneFolder.project, directoryHint: .notDirectory)
    guard isInside(projectFile, folder) else { return .failure(.wallpaperEngine(.escapesFolder(SceneFolder.project))) }
    let project: WallpaperEngineProject
    do {
        project = try WallpaperEngineProject.parse(data)
    } catch {
        return .failure(.wallpaperEngine(error))
    }

    let preview = project.preview
        .map { folder.appending(path: $0, directoryHint: .notDirectory) }
        .flatMap { FileManager.default.fileExists(atPath: $0.path) && isInside($0, folder) ? $0 : nil }

    switch project.kind {
    case .video:
        let file = folder.appending(path: project.file, directoryHint: .notDirectory)
        guard FileManager.default.fileExists(atPath: file.path) else { return .failure(.missingFile(project.file)) }
        // The parser checked the name. This checks where the name really leads.
        guard isInside(file, folder) else { return .failure(.wallpaperEngine(.escapesFolder(project.file))) }
        let name = project.title ?? file.deletingPathExtension().lastPathComponent
        return .success(ImportCandidate(source: file, name: name, preview: preview))

    case .scene:
        // The scene's JSON is inside the package the project's file names.
        let name = SceneFolder.itemPackage(for: project.file)
        let package = folder.appending(path: name, directoryHint: .notDirectory)
        guard FileManager.default.fileExists(atPath: package.path) else { return .failure(.noScenePackage(name)) }
        guard isInside(package, folder) else { return .failure(.wallpaperEngine(.escapesFolder(project.file))) }
        let scene = SceneItem(project: projectFile, sceneFile: project.file)
        return .success(ImportCandidate(source: package, name: project.title ?? folder.lastPathComponent, preview: preview, scene: scene))
    }
}

/// Whether `file`, its links followed, is somewhere inside `folder`, its links followed too.
func isInside(_ file: URL, _ folder: URL) -> Bool {
    let folderSteps = folder.resolvingSymlinksInPath().pathComponents
    let fileSteps = file.resolvingSymlinksInPath().pathComponents
    return fileSteps.count > folderSteps.count && fileSteps.starts(with: folderSteps)
}
