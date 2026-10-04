import Foundation
import Synchronization
import Testing
import LivepaperCore
import LivepaperImport

/// A cancelled or failed import leaves nothing behind, and the manifest never names files that are not there.
/// A library that loses power as the manifest is saved.
private actor FailingLibrary: ImportLibrary {
    struct PowerCut: Error {}
    var inserts = 0

    func wallpaper(withFingerprint fingerprint: Fingerprint) -> Wallpaper? { nil }
    func wallpaper(withID id: WallpaperID) -> Wallpaper? { nil }
    func insert(_ wallpaper: Wallpaper) throws {
        inserts += 1
        throw PowerCut()
    }
}

struct ImportSafetyTests {
    let bench: ImportBench

    init() throws {
        bench = try ImportBench()
    }

    /// Runs an import and cancels it the moment it reports `stage`, or that much of it done.
    func cancelling(
        at stage: ImportStage, after fraction: Double = 0, _ source: String, ffmpeg: FFmpegTool? = nil
    ) async throws -> Result<ImportOutcome, any Error> {
        let importer = bench.importer(ffmpeg: ffmpeg)
        let candidate = ImportCandidate(source: try Fixture.url(source), name: "Cancelled")
        let running = Mutex<Task<ImportOutcome, any Error>?>(nil)
        let (start, open) = AsyncStream<Void>.makeStream()

        let task = Task {
            for await _ in start { break }
            return try await importer.run(candidate) { progress in
                if progress.stage == stage, progress.fraction ?? 0 >= fraction { running.withLock { $0?.cancel() } }
            }
        }
        running.withLock { $0 = task }
        open.yield()
        return await task.result
    }

    static let stagesBeforeCommit: [ImportStage] = [.fingerprint, .probe, .normalise, .validate, .artefacts]

    @Test(arguments: stagesBeforeCommit)
    func `cancelling at any stage leaves nothing behind`(stage: ImportStage) async throws {
        let result = try await cancelling(at: stage, "bframes-edit-list.mp4")

        #expect(throws: CancellationError.self) { try result.get() }
        #expect(bench.stagingResidue.isEmpty)
        #expect(bench.wallpaperFolders.isEmpty)
        #expect(try bench.savedLibrary().wallpapers.isEmpty)
    }

    @Test func `cancelling with the optimised copy half written leaves nothing behind`() async throws {
        let result = try await cancelling(at: .normalise, after: 0.4, "bframes-long-audio.mp4")

        #expect(throws: CancellationError.self) { try result.get() }
        #expect(bench.stagingResidue.isEmpty)
        #expect(bench.wallpaperFolders.isEmpty)
    }

    @Test(.enabled(if: Helper.shouldRun))
    func `cancelling while ffmpeg converts stops it and leaves nothing behind`() async throws {
        let result = try await cancelling(at: .convert, "vp9-opus.webm", ffmpeg: Helper.required())

        #expect(throws: CancellationError.self) { try result.get() }
        #expect(bench.stagingResidue.isEmpty)
        #expect(bench.wallpaperFolders.isEmpty)
    }

    @Test(.enabled(if: Helper.shouldRun))
    func `a conversion that outgrows the size limit fails the import and leaves nothing behind`() async throws {
        var ffmpeg = try Helper.required()
        ffmpeg.limits.outputBytes = 20_000

        await #expect(throws: FFmpegError.sizeLimitExceeded) {
            try await bench.importer(ffmpeg: ffmpeg).run(ImportCandidate(source: Fixture.url("vp9-opus.webm"), name: "Rain"))
        }
        #expect(bench.stagingResidue.isEmpty)
        #expect(bench.wallpaperFolders.isEmpty)
    }

    @Test func `a cancel that arrives with the commit does not split it`() async throws {
        let result = try await cancelling(at: .commit, "plain-h264.mp4")

        // Whichever way it went, it went all the way.
        let saved = try bench.savedLibrary().wallpapers.map(\.id.description)
        #expect(bench.wallpaperFolders == saved)
        #expect(bench.stagingResidue.isEmpty)
        if case .success(.imported(let wallpaper, _)) = result { #expect(saved == [wallpaper.id.description]) }
    }

    // MARK: Killed between the steps of a commit

    @Test func `when the manifest cannot be saved the files go again: no orphan folder`() async throws {
        let library = FailingLibrary()

        await #expect(throws: FailingLibrary.PowerCut.self) {
            try await bench.importer(library: library).run(ImportCandidate(source: Fixture.url("plain-h264.mp4"), name: "Holiday"))
        }
        #expect(await library.inserts == 1)
        #expect(bench.wallpaperFolders.isEmpty)
        #expect(bench.stagingResidue.isEmpty)
    }

    @Test func `when the rename fails the manifest is never touched: no entry without files`() async throws {
        // Wallpaper 1's folder is already there, so the rename into place cannot succeed.
        let taken = bench.location.root.appending(path: "wallpapers/AAAAAAAA-0000-0000-0000-000000000001/keep.txt")
        try FileManager.default.createDirectory(at: taken.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not the importer's".utf8).write(to: taken)

        await #expect(throws: (any Error).self) {
            try await bench.importer().run(ImportCandidate(source: Fixture.url("plain-h264.mp4"), name: "Holiday"))
        }
        #expect(try bench.savedLibrary().wallpapers.isEmpty)
        #expect(await bench.library.library.wallpapers.isEmpty)
        #expect(bench.stagingResidue.isEmpty)
        #expect(FileManager.default.fileExists(atPath: taken.path), "what was there is not the importer's to remove")
    }

    @Test func `two imports of the same file at once make one wallpaper`() async throws {
        let importer = bench.importer()
        let candidate = ImportCandidate(source: try Fixture.url("plain-h264.mp4"), name: "Holiday")

        async let first = importer.run(candidate)
        async let second = importer.run(candidate)
        let outcomes = try await [first, second]

        let library = try bench.savedLibrary()
        #expect(library.wallpapers.count == 1)
        #expect(bench.wallpaperFolders == library.wallpapers.map(\.id.description))
        #expect(bench.stagingResidue.isEmpty)
        #expect(outcomes.count { if case .imported = $0 { true } else { false } } == 1)
        #expect(outcomes.contains(.duplicate(of: library.wallpapers[0])))
    }

    @Test(.timeLimit(.minutes(2)))
    func `a batch larger than the Mac has cores does not starve itself`() async throws {
        // Reading a track blocks. Done on Swift's own threads, one per core, this many at once never came back.
        let source = try Fixture.url("bframes-edit-list.mp4")
        let batch = ProcessInfo.processInfo.activeProcessorCount * 4

        let reports = try await withThrowingTaskGroup(of: ProbeResult.self) { group in
            for _ in 0..<batch { group.addTask { try await probeSource(at: source) } }
            return try await group.reduce(into: []) { $0.append($1) }
        }

        #expect(reports.count == batch)
        #expect(Set(reports.map { $0.video?.frameCount }) == [60])
    }

    // MARK: After a real kill

    @Test func `the sweep at launch removes what a killed import left, and nothing else`() async throws {
        let candidate = ImportCandidate(source: try Fixture.url("plain-h264.mp4"), name: "Kept")
        guard case .imported(let kept, _) = try await bench.importer().run(candidate) else {
            Issue.record("the import failed")
            return
        }
        // Killed while converting, and killed between the rename and the manifest.
        let root = "Library/Application Support/Livepaper"
        try bench.home.write("half a movie", to: "\(root)/.staging/AAAAAAAA-0000-0000-0000-000000000007/wallpaper.mov")
        try bench.home.write("a whole movie", to: "\(root)/wallpapers/AAAAAAAA-0000-0000-0000-000000000008/wallpaper.mov")

        let removed = try sweepInterruptedImports(in: bench.location)

        #expect(removed.map(\.lastPathComponent).sorted() == [
            "AAAAAAAA-0000-0000-0000-000000000007", "AAAAAAAA-0000-0000-0000-000000000008",
        ])
        #expect(bench.stagingResidue.isEmpty)
        #expect(bench.wallpaperFolders == [kept.id.description])
        #expect(FileManager.default.fileExists(atPath: bench.location.url(for: kept.optimisedCopy).path))
    }

    @Test func `with a manifest that cannot be read, the sweep leaves every wallpaper where it is`() async throws {
        // The app goes on with the manifest before this one, which does not list the newest wallpaper.
        // Its files are not leftovers.
        let candidate = ImportCandidate(source: try Fixture.url("plain-h264.mp4"), name: "Newest")
        guard case .imported(let newest, _) = try await bench.importer().run(candidate) else {
            Issue.record("the import failed")
            return
        }
        try bench.home.write("half a movie", to: "Library/Application Support/Livepaper/.staging/AAAAAAAA-0000-0000-0000-000000000007/x")
        try Data("{ cut short".utf8).write(to: bench.location.manifest)

        let removed = try sweepInterruptedImports(in: bench.location)

        #expect(removed.map(\.lastPathComponent) == ["AAAAAAAA-0000-0000-0000-000000000007"])
        #expect(FileManager.default.fileExists(atPath: bench.location.url(for: newest.optimisedCopy).path))
    }

    @Test func `a library that was never imported into has nothing to sweep`() throws {
        #expect(try sweepInterruptedImports(in: bench.location).isEmpty)
    }
}
