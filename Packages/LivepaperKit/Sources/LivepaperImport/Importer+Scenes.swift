import CoreGraphics
import Foundation
import ImageIO
import LivepaperCore
import LivepaperScene

// Wallpaper Engine scenes. A GIF scene's frames are an exact
// loop, so they become a video and go the video's way. Any other scene is
// kept as its own files, to be drawn live: fingerprint, probe (the package
// read), prepare (the files copied in, then its shaders translated), artefacts
// (the poster, drawn from the scene or else cut from the item's preview, and
// the hover preview), commit.

extension Importer {
    func importScene(
        _ candidate: ImportCandidate, _ item: SceneItem, fingerprint: Fingerprint, progress: @escaping @Sendable (ImportProgress) -> Void
    ) async throws -> ImportOutcome {
        progress(ImportProgress(stage: .probe))
        let outline: SceneOutline
        let package: ScenePackage
        do {
            package = try ScenePackage(contentsOf: candidate.source)
            outline = try readSceneOutline(of: item.sceneFile, in: package)
        } catch let error as SceneReadError {
            throw ImportError.scene(error)
        }
        if let texture = outline.spriteSheet, let data = package.entry(texture), let sheet = try? SpriteSheet(texture: data) {
            return try await importGIFScene(candidate, sheet, over: outline.clearColour, fingerprint: fingerprint, progress: progress)
        }
        guard let size = outline.size else { throw ImportError.sceneWithoutSize }

        let id = makeID()
        let staging = location.staging.appending(path: id.description, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            progress(ImportProgress(stage: .prepare))
            let packageName = try copySceneFiles(candidate, item, into: staging)
            // A scene that is not prepared is kept all the same, holding its poster; the app prepares it again later.
            let preparation = try await prepareScene(staging)

            try Task.checkCancellation()
            progress(ImportProgress(stage: .artefacts))
            let poster = try await writeScenePoster(in: staging, size: size, preview: candidate.preview)
            let hasHoverPreview = try await makeHoverPreview(fromGIF: candidate.preview, in: staging)

            let folder = "\(location.wallpapers.lastPathComponent)/\(id)"
            let name = candidate.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let (width, height) = (Int(size.width), Int(size.height))
            let wallpaper = Wallpaper(
                id: id,
                name: name.isEmpty ? "Wallpaper" : name,
                importedAt: now(),
                fingerprint: fingerprint,
                optimisedCopy: try LibraryPath("\(folder)/\(packageName)"),
                poster: try LibraryPath("\(folder)/\(File.poster)"),
                hoverPreview: hasHoverPreview ? try LibraryPath("\(folder)/\(File.hoverPreview)") : nil,
                // No length, since a scene does not loop; the rate it is drawn at; the bytes of its folder.
                details: WallpaperDetails(
                    duration: 0, width: width, height: height, frameRate: LivepaperScene.framesPerSecond,
                    codec: "scene", byteCount: byteCount(of: staging)
                ),
                scene: WallpaperScene(project: try LibraryPath("\(folder)/\(SceneFolder.project)"), width: width, height: height)
            )

            try Task.checkCancellation()
            progress(ImportProgress(stage: .commit))
            // From here the import runs to its end, as a video's does.
            let outcome = ImportOutcome.importedScene(wallpaper, preparation: preparation, poster: poster)
            return try await commit(staging, as: wallpaper, answering: outcome)
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    /// The sprite sheet written out as a video, then the video's own way from
    /// the plan on. The intermediate file never reaches the library.
    private func importGIFScene(
        _ candidate: ImportCandidate, _ sheet: SpriteSheet, over background: [Double], fingerprint: Fingerprint,
        progress: @escaping @Sendable (ImportProgress) -> Void
    ) async throws -> ImportOutcome {
        let id = makeID()
        let staging = location.staging.appending(path: id.description, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            let frames = staging.appending(path: File.spriteSheet)
            progress(ImportProgress(stage: .convert, fraction: 0))
            try await writeSpriteSheetVideo(sheet, over: background, to: frames) { progress(ImportProgress(stage: .convert, fraction: $0)) }
            let probe = try await probeSource(at: frames)
            let staged = try await build(frames, probe: probe, plan: planImport(probe), in: staging, progress: progress)
            try FileManager.default.removeItem(at: frames)
            let wallpaper = try wallpaper(id: id, name: candidate.name, fingerprint: fingerprint, staged: staged)

            try Task.checkCancellation()
            progress(ImportProgress(stage: .commit))
            return try await commit(staging, as: wallpaper, answering: .imported(wallpaper, staged.report))
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    /// The item's own files, as the scene's folder keeps them: `project.json`,
    /// the package and the preview, under the names the project gives them
    /// (the package's made plain, `SceneFolder.package(for:)`). Not the
    /// `shaders/` folder beside them, Wallpaper Engine's own cache of compiled
    /// DirectX shaders. Answers the package's name in the folder.
    ///
    /// A file that is a link is copied as the file it leads to, and only while
    /// that is inside the item's folder: discovery looked, but the folder may
    /// have changed since, and the library keeps files, never links.
    private func copySceneFiles(_ candidate: ImportCandidate, _ item: SceneItem, into staging: URL) throws -> String {
        let packageName = SceneFolder.package(for: item.sceneFile)
        var copies = [(item.project, SceneFolder.project), (candidate.source, packageName)]
        // Discovery found the preview inside the item's folder; it keeps its place in it.
        let itemFolder = item.project.deletingLastPathComponent()
        if let preview = candidate.preview, preview.pathComponents.starts(with: itemFolder.pathComponents) {
            let name = preview.pathComponents.dropFirst(itemFolder.pathComponents.count).joined(separator: "/")
            if ![SceneFolder.project, packageName, SceneFolder.poster, SceneFolder.hoverPreview].contains(name) {
                copies.append((preview, name))
            }
        }
        for (from, name) in copies {
            guard isInside(from, itemFolder) else {
                throw WallpaperEngineProjectError.escapesFolder(from.lastPathComponent)
            }
            let to = staging.appending(path: name, directoryHint: .notDirectory)
            try FileManager.default.createDirectory(at: to.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: from.resolvingSymlinksInPath(), to: to)
        }
        return packageName
    }

    /// The scene's poster, drawn from the scene prepared in `staging` (`ScenePoster`), or,
    /// when it cannot be drawn, cut from the item's preview; with neither, the import fails.
    private func writeScenePoster(in staging: URL, size: Size, preview: URL?) async throws -> ScenePoster.Outcome {
        let poster = staging.appending(path: File.poster)
        var drawn = ScenePoster.Outcome.notDrawn(reason: "nothing draws scenes here")
        if let sceneDrawing {
            drawn = try await ScenePoster.draw(staging, size: size, drawing: sceneDrawing, to: poster)
        }
        if case .notDrawn = drawn { try makeScenePoster(from: preview, shape: size, at: poster) }
        return drawn
    }

    /// A scene's hover preview, from the item's `preview.gif` when it has one:
    /// converted by the ffmpeg helper as any GIF is, then made small and slow
    /// like a video's. A nicety, left out when there is no GIF, no helper, or
    /// anything goes wrong.
    private func makeHoverPreview(fromGIF preview: URL?, in staging: URL) async throws -> Bool {
        guard let preview, let ffmpeg, isAnimated(preview) else { return false }
        let converted = staging.appending(path: File.intermediate)
        defer { try? FileManager.default.removeItem(at: converted) }
        do {
            try await ffmpeg.convert(preview, to: converted) { _ in }
            guard let video = try await probeSource(at: converted).video else { return false }
            return try await makeHoverPreview(
                of: converted, rate: FrameRate.forOptimisedCopy(of: video), at: staging.appending(path: File.hoverPreview)
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return false
        }
    }

    private func isAnimated(_ picture: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(picture as CFURL, nil) else { return false }
        return CGImageSourceGetCount(source) > 1
    }

    private func byteCount(of folder: URL) -> Int {
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.compactMap { ($0 as? URL).flatMap { try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize } }.reduce(0, +)
    }
}
