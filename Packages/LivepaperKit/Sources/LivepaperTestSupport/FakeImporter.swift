import CryptoKit
import Foundation
import LivepaperCore
import LivepaperImport

/// An importer that reads and writes nothing, for tests and the app's fakes
/// run: it walks the stages on its clock, a step after each report, and inserts
/// the wallpaper its factory makes through the library it was given.
///
/// Its fingerprint is the SHA-256 of the source file's path, not of its bytes,
/// so the file need not be there and a large one costs nothing: the same file
/// imported again is a duplicate, a copy of it under another name is not.
/// The files the real importer sends through the ffmpeg helper are told by
/// their extension. A candidate whose name contains "fail" is rejected at the
/// probe. Dropping the stream stops it at the next step.
public struct FakeImporter<C: Clock>: ImportRunning where C.Duration == Duration {
    private let library: any ImportLibrary
    private let clock: C
    private let step: Duration
    private let makeWallpaper: @Sendable (ImportCandidate, Fingerprint) -> Wallpaper

    /// `makeWallpaper` makes what an import of the candidate becomes. It must give the wallpaper the
    /// fingerprint: that is how the library knows the file the next time.
    public init(
        library: any ImportLibrary,
        clock: C,
        step: Duration,
        makeWallpaper: @escaping @Sendable (_ candidate: ImportCandidate, _ fingerprint: Fingerprint) -> Wallpaper
    ) {
        self.library = library
        self.clock = clock
        self.step = step
        self.makeWallpaper = makeWallpaper
    }

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

    /// At once, off the clock: a path costs nothing to hash.
    public func existingWallpaper(for candidate: ImportCandidate) async throws -> Wallpaper? {
        try await library.wallpaper(withFingerprint: Self.fingerprint(of: candidate))
    }

    private func run(_ candidate: ImportCandidate, progress: (ImportProgress) -> Void) async throws -> ImportOutcome {
        let fingerprint = Self.fingerprint(of: candidate)
        try await walk(.fingerprint, progress)
        if let existing = try await library.wallpaper(withFingerprint: fingerprint) { return .duplicate(of: existing) }

        try await walk(.probe, progress)
        if candidate.name.localizedCaseInsensitiveContains("fail") { throw ImportError.rejected(.unrecognised) }
        let plan: ImportPlan = helperExtensions.contains(candidate.source.pathExtension.lowercased()) ? .ffmpeg : .remux
        if plan == .ffmpeg { try await walk(.convert, fractions: true, progress) }
        try await walk(.normalise, fractions: true, progress)
        try await walk(.validate, progress)
        try await walk(.artefacts, progress)

        // As the real importer: a cancel is heard up to here, and the commit then runs to its end.
        try Task.checkCancellation()
        progress(ImportProgress(stage: .commit))
        let wallpaper = makeWallpaper(candidate, fingerprint)
        try await library.insert(wallpaper)
        return .imported(wallpaper, ImportReport(plan: plan, writtenBy: .remux, seam: Self.cleanSeam))
    }

    /// Reports the stage, a quarter at a time when it can tell how far it is, and waits a step after each report.
    private func walk(_ stage: ImportStage, fractions: Bool = false, _ progress: (ImportProgress) -> Void) async throws {
        for fraction in fractions ? [0, 0.25, 0.5, 0.75, 1] : [nil] {
            progress(ImportProgress(stage: stage, fraction: fraction))
            try await clock.sleep(until: clock.now.advanced(by: step), tolerance: nil)
        }
    }

    /// The SHA-256 of the source file's path.
    private static func fingerprint(of candidate: ImportCandidate) -> Fingerprint {
        let digest = SHA256.hash(data: Data(candidate.source.path.utf8))
        return Fingerprint(sha256: digest.map { String(format: "%02x", $0) }.joined())
    }

    /// One frame with nothing wrong at its seam.
    private static var cleanSeam: LoopSeamReport {
        let frame = TrackReading.Frame(pts: 0, duration: 20, isSync: true)
        return judgeLoopSeam(TrackReading(timescale: 600, frames: [frame], trackDuration: 20, hasEditList: false))
    }
}

/// What the real importer sends through the ffmpeg helper.
private let helperExtensions: Set = ["webm", "mkv", "avi", "wmv", "gif"]
