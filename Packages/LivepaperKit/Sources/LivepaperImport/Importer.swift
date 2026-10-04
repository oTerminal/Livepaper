import Foundation
import LivepaperCore
import LivepaperScene

public enum ImportStage: String, Equatable, Sendable, CaseIterable {
    case fingerprint
    case probe
    /// The ffmpeg helper, for the files AVFoundation cannot open. Skipped for the rest.
    case convert
    /// Writing the optimised copy: a remux or a transcode, either of which leaves the timing clean.
    case normalise
    case validate
    /// A scene's own work before it is committed: its files copied in, then its
    /// shaders translated to Metal (`ScenePreparation`).
    case prepare
    case artefacts
    case commit
}

public struct ImportProgress: Equatable, Sendable {
    public let stage: ImportStage
    /// 0 to 1 within the stage. Nil when the stage cannot tell.
    public let fraction: Double?

    public init(stage: ImportStage, fraction: Double? = nil) {
        self.stage = stage
        self.fraction = fraction
    }
}

/// The two ways an optimised copy is written.
public enum CopyWriter: Equatable, Sendable {
    case remux
    case transcode
}

/// How an import got to its optimised copy, for the diagnostics export and the tests.
public struct ImportReport: Equatable, Sendable {
    /// What the planner made of the source file.
    public var plan: ImportPlan
    /// What wrote the optimised copy that was kept.
    public var writtenBy: CopyWriter
    /// The validator's findings on the optimised copy.
    public var seam: LoopSeamReport

    public init(plan: ImportPlan, writtenBy: CopyWriter, seam: LoopSeamReport) {
        self.plan = plan
        self.writtenBy = writtenBy
        self.seam = seam
    }
}

public enum ImportOutcome: Equatable, Sendable {
    case imported(Wallpaper, ImportReport)
    /// A scene, kept as it is to be drawn live: there is no
    /// optimised copy to report on, only how its preparation went and how its
    /// poster was made. One that was not prepared is imported all the same, and
    /// holds its poster until it is; a poster not drawn from the scene is cut
    /// from the item's preview, and drawn at a later launch (`ScenePoster`).
    /// A GIF scene is `imported`, as the video it became.
    case importedScene(Wallpaper, preparation: ScenePreparation.Outcome, poster: ScenePoster.Outcome)
    /// The same source file was imported before, as this wallpaper. Nothing was written.
    case duplicate(of: Wallpaper)
}

public enum ImportError: Error, Equatable, Sendable {
    case rejected(RejectReason)
    /// The scene's package, or the scene in it, cannot be read.
    case scene(SceneReadError)
    /// The scene has no size of its own (`orthogonalprojection`) to lay it out
    /// on a display: a scene in perspective, or one that sizes itself.
    case sceneWithoutSize
    /// The file needs the ffmpeg helper and there is none.
    case helperMissing
    /// The helper converted the file, and AVFoundation cannot read what it made.
    case helperOutputUnreadable
    /// The optimised copy would not loop without a gap, even transcoded. The report says what was wrong with it.
    case loopSeam(LoopSeamReport)
}

public enum ImportEvent: Equatable, Sendable {
    case progress(ImportProgress)
    case finished(ImportOutcome)
}

/// What to do with an optimised copy once the validator has read it: a
/// failure sends the file back through transcode once, then rejects.
public enum SeamVerdict: Equatable, Sendable {
    case keep
    case transcodeAgain
    case reject
}

public func judgeAttempt(_ report: LoopSeamReport, transcodesSoFar retries: Int) -> SeamVerdict {
    if report.passes { return .keep }
    return retries == 0 ? .transcodeAgain : .reject
}

/// What runs an import: the real `Importer`, or a fake one in tests and the app's fakes run.
public protocol ImportRunning: Sendable {
    /// The import as a stream of events, ending with `.finished`. Letting go of the stream cancels the import.
    func events(importing candidate: ImportCandidate) -> AsyncThrowingStream<ImportEvent, any Error>
    /// The wallpaper the library already has for the candidate's source file,
    /// found by its fingerprint as an import would find it; nil for a new file.
    /// Reads the file and writes nothing, so it can run beside an import.
    func existingWallpaper(for candidate: ImportCandidate) async throws -> Wallpaper?
}

extension Importer: ImportRunning {}

/// Turns a source file into a wallpaper in the library: one optimised copy
/// that loops without a gap, a poster and a hover preview. A Wallpaper Engine
/// scene is kept as its own files instead, to be drawn live, and a GIF scene
/// becomes a video (`Importer+Scenes.swift`).
///
/// The source file is only ever read. Everything is built in `.staging/<id>/`
/// and renamed into place at the end, and a failed or cancelled import leaves
/// nothing behind.
public struct Importer: Sendable {
    public let location: LibraryLocation
    let library: any ImportLibrary
    let ffmpeg: FFmpegTool?
    let validate: @Sendable (URL) async throws -> LoopSeamReport
    /// A scene's import-time work, on its folder in `.staging/` (`ImportStage.prepare`).
    /// Only a cancel throws; a scene it could not prepare is imported all the same.
    let prepareScene: @Sendable (URL) async throws -> ScenePreparation.Outcome
    /// What draws a scene's poster once it is prepared (`ScenePoster`); with none, it is cut from the item's preview.
    let sceneDrawing: SceneDrawingType?
    let makeID: @Sendable () -> WallpaperID
    let now: @Sendable () -> Date

    public init(
        location: LibraryLocation,
        library: any ImportLibrary,
        ffmpeg: FFmpegTool?,
        shaderTools: ShaderTools?,
        validate: (@Sendable (URL) async throws -> LoopSeamReport)? = nil,
        prepareScene: (@Sendable (URL) async throws -> ScenePreparation.Outcome)? = nil,
        sceneDrawing: (any SceneDrawing.Type)? = nil,
        makeID: @escaping @Sendable () -> WallpaperID = { WallpaperID(uuid: UUID()) },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.location = location
        self.library = library
        self.ffmpeg = ffmpeg
        // Made here, not as a default argument: Swift 6.2 miscompiles an async closure
        // there, and the import aborted with "freed pointer was not the last allocation".
        self.validate = validate ?? { try await validateLoopSeam(of: $0) }
        // The shader tools are the default hook's: a hook given in their place needs none.
        self.prepareScene = prepareScene ?? { try await ScenePreparation.prepare($0, tools: shaderTools) }
        self.sceneDrawing = sceneDrawing.map(SceneDrawingType.init)
        self.makeID = makeID
        self.now = now
    }

    /// The import as a stream of events, ending with `.finished`. Letting go of the stream cancels the import.
    public func events(importing candidate: ImportCandidate) -> AsyncThrowingStream<ImportEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let outcome = try await run(candidate) { continuation.yield(.progress($0)) }
                    continuation.yield(.finished(outcome))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// The whole file is hashed, so this runs off the caller's actor, as `run` does.
    @concurrent
    public func existingWallpaper(for candidate: ImportCandidate) async throws -> Wallpaper? {
        try await library.wallpaper(withFingerprint: fingerprint(of: candidate.source))
    }

    @concurrent
    public func run(
        _ candidate: ImportCandidate, progress: @escaping @Sendable (ImportProgress) -> Void = { _ in }
    ) async throws -> ImportOutcome {
        let source = candidate.source

        progress(ImportProgress(stage: .fingerprint))
        let fingerprint = try await fingerprint(of: source)
        if let existing = try await library.wallpaper(withFingerprint: fingerprint) { return .duplicate(of: existing) }
        if let scene = candidate.scene {
            return try await importScene(candidate, scene, fingerprint: fingerprint, progress: progress)
        }

        progress(ImportProgress(stage: .probe))
        let probe = try await probeSource(at: source)
        let plan = planImport(probe)
        if case .reject(let reason) = plan { throw ImportError.rejected(reason) }
        if plan == .ffmpeg, ffmpeg == nil { throw ImportError.helperMissing }

        let id = makeID()
        let staging = location.staging.appending(path: id.description, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        do {
            let staged = try await build(source, probe: probe, plan: plan, in: staging, progress: progress)
            let wallpaper = try wallpaper(id: id, name: candidate.name, fingerprint: fingerprint, staged: staged)

            try Task.checkCancellation()
            progress(ImportProgress(stage: .commit))
            // From here the import runs to its end: a cancel must not land between the rename and the manifest.
            return try await commit(staging, as: wallpaper, answering: .imported(wallpaper, staged.report))
        } catch {
            try? FileManager.default.removeItem(at: staging)
            throw error
        }
    }

    // MARK: Stages

    struct Staged {
        var details: WallpaperDetails
        var hasHoverPreview: Bool
        var report: ImportReport
    }

    enum File {
        static let optimisedCopy = "wallpaper.mov"
        static let poster = "poster.heic"
        static let hoverPreview = "hover.mov"
        static let intermediate = "ffmpeg.mov"
        /// A GIF scene's frames, before they become the optimised copy.
        static let spriteSheet = "sprite-sheet.mov"
    }

    func build(
        _ source: URL, probe: ProbeResult, plan: ImportPlan, in staging: URL, progress: @escaping @Sendable (ImportProgress) -> Void
    ) async throws -> Staged {
        // What the optimised copy is written from: the source file, or what ffmpeg made of it.
        var material = (url: source, probe: probe, plan: plan)
        let intermediate = staging.appending(path: File.intermediate)
        if plan == .ffmpeg, let ffmpeg {
            progress(ImportProgress(stage: .convert, fraction: 0))
            try await ffmpeg.convert(source, to: intermediate) { progress(ImportProgress(stage: .convert, fraction: $0)) }
            let converted = try await probeSource(at: intermediate)
            material = (intermediate, converted, planImport(converted))
        }
        if case .reject(let reason) = material.plan { throw ImportError.rejected(reason) }
        guard let video = material.probe.video, material.plan != .ffmpeg else { throw ImportError.helperOutputUnreadable }

        let optimisedCopy = staging.appending(path: File.optimisedCopy)
        let rate = FrameRate.forOptimisedCopy(of: video)
        var writtenBy: CopyWriter = material.plan == .remux ? .remux : .transcode
        var transcodes = 0
        var seam: LoopSeamReport
        while true {
            let report: @Sendable (Double) -> Void = { progress(ImportProgress(stage: .normalise, fraction: $0)) }
            report(0)
            switch writtenBy {
            case .remux: try await remux(material.url, to: optimisedCopy, rate: rate, progress: report)
            case .transcode: try await transcodeOptimisedCopy(material.url, of: video, rate: rate, to: optimisedCopy, progress: report)
            }

            progress(ImportProgress(stage: .validate))
            seam = try await validate(optimisedCopy)
            let verdict = judgeAttempt(seam, transcodesSoFar: transcodes)
            if verdict == .keep { break }
            guard verdict == .transcodeAgain else { throw ImportError.loopSeam(seam) }
            try FileManager.default.removeItem(at: optimisedCopy)
            writtenBy = .transcode
            transcodes += 1
        }
        // The library keeps only the optimised copy: what ffmpeg made must not be renamed into place with it.
        if FileManager.default.fileExists(atPath: intermediate.path) { try FileManager.default.removeItem(at: intermediate) }

        progress(ImportProgress(stage: .artefacts))
        try await makePoster(of: optimisedCopy, at: staging.appending(path: File.poster))
        let hasHoverPreview = try await makeHoverPreview(of: optimisedCopy, rate: rate, at: staging.appending(path: File.hoverPreview))

        return Staged(
            details: try await details(of: optimisedCopy),
            hasHoverPreview: hasHoverPreview,
            report: ImportReport(plan: plan, writtenBy: writtenBy, seam: seam)
        )
    }

    /// The hover preview is a nicety. One that cannot be made, or would not
    /// loop, is left out, and the wallpaper is imported without it.
    func makeHoverPreview(of optimisedCopy: URL, rate: FrameRate, at destination: URL) async throws -> Bool {
        do {
            try await transcode(optimisedCopy, to: destination, as: .hoverPreview(of: rate)) { _ in }
            if try await validate(destination).passes { return true }
        } catch is CancellationError {
            throw CancellationError()
        } catch {}
        try? FileManager.default.removeItem(at: destination)
        return false
    }

    private func details(of optimisedCopy: URL) async throws -> WallpaperDetails {
        guard let video = try await probeSource(at: optimisedCopy).video else { throw MediaError.noVideoTrack }
        let byteCount = try FileManager.default.attributesOfItem(atPath: optimisedCopy.path)[.size] as? Int ?? 0
        let codec = VideoProbe.keptCodecs[video.codec] ?? video.codec
        return WallpaperDetails(
            duration: video.duration, width: video.width, height: video.height,
            frameRate: (video.nominalFrameRate * 100).rounded() / 100, codec: codec, byteCount: byteCount
        )
    }

    func wallpaper(id: WallpaperID, name: String, fingerprint: Fingerprint, staged: Staged) throws -> Wallpaper {
        let folder = "\(location.wallpapers.lastPathComponent)/\(id)"
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return Wallpaper(
            id: id,
            name: name.isEmpty ? "Wallpaper" : name,
            importedAt: now(),
            fingerprint: fingerprint,
            optimisedCopy: try LibraryPath("\(folder)/\(File.optimisedCopy)"),
            poster: try LibraryPath("\(folder)/\(File.poster)"),
            hoverPreview: staged.hasHoverPreview ? try LibraryPath("\(folder)/\(File.hoverPreview)") : nil,
            details: staged.details
        )
    }

    /// The rename first, the manifest after it: a manifest never names files
    /// that are not there. If the manifest cannot be saved, the files go again.
    /// Answers `outcome`, or a duplicate when another import of the same file got there first.
    func commit(_ staging: URL, as wallpaper: Wallpaper, answering outcome: ImportOutcome) async throws -> ImportOutcome {
        let folder = location.wallpapers.appending(path: wallpaper.id.description, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: location.wallpapers, withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: staging, to: folder)
        do {
            try await library.insert(wallpaper)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            // Another import of the same file got there first.
            if case LibraryError.duplicate(let id) = error, let winner = try? await library.wallpaper(withID: id) {
                return .duplicate(of: winner)
            }
            throw error
        }
        return outcome
    }
}
