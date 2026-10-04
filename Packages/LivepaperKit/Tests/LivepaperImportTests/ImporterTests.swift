import Foundation
import Testing
import LivepaperCore
import LivepaperImport

/// The fixture corpus through the whole pipeline. What the files are is written in `Fixtures/make-fixtures.sh`.
struct ImporterTests {
    let bench: ImportBench

    init() throws {
        bench = try ImportBench()
    }

    struct Expected: Sendable {
        var plan: ImportPlan
        var writtenBy: CopyWriter
        var codec: String
        var hasAudio = false
        var size: [Int] = [320, 180]
        var frameRate: Double = 30
        var frames: Int = 60

        static func kept(hasAudio: Bool = false) -> Expected {
            Expected(plan: .remux, writtenBy: .remux, codec: "h264", hasAudio: hasAudio)
        }

        static func transcoded(hasAudio: Bool = false, size: [Int] = [320, 180]) -> Expected {
            Expected(plan: .transcode, writtenBy: .transcode, codec: "hevc", hasAudio: hasAudio, size: size)
        }

        /// Converted by ffmpeg with no B-frames and a constant rate, so that what it made could be kept as it was.
        static func converted(hasAudio: Bool = false, size: [Int] = [320, 180], frameRate: Double = 30, frames: Int = 60) -> Expected {
            Expected(plan: .ffmpeg, writtenBy: .remux, codec: "hevc", hasAudio: hasAudio, size: size, frameRate: frameRate, frames: frames)
        }
    }

    /// Imports a source file and checks what every import has to leave behind, whatever it started from.
    func importAndCheck(_ candidate: ImportCandidate, with importer: Importer, against expected: Expected) async throws {
        let before = try Data(contentsOf: candidate.source)
        let outcome = try await importer.run(candidate)
        #expect(try Data(contentsOf: candidate.source) == before, "the source file is never modified")

        guard case .imported(let wallpaper, let report) = outcome else {
            Issue.record("not imported: \(outcome)")
            return
        }
        #expect(report.plan == expected.plan)
        #expect(report.writtenBy == expected.writtenBy)
        #expect(report.seam.passes)

        // The optimised copy: no seam, by a reading of the file as it lies in the library, and nothing left to normalise.
        let optimisedCopy = bench.location.url(for: wallpaper.optimisedCopy)
        let seam = try await validateLoopSeam(of: optimisedCopy)
        #expect(seam.passes, "\(seam)")
        #expect(seam.frameCount == expected.frames)
        let probe = try await probeSource(at: optimisedCopy)
        #expect(planImport(probe) == .remux)
        #expect(probe.video?.transferFunction == .sdr)
        #expect(probe.video?.orientation == .upright)
        // The audio is kept, and trimmed to the video, never the reverse.
        #expect((probe.audio != nil) == expected.hasAudio)
        if let audio = probe.audio, let video = probe.video {
            #expect(audio.duration <= video.duration)
            #expect(audio.duration > video.duration - 0.1)
        }

        #expect(wallpaper.details.codec == expected.codec)
        #expect([wallpaper.details.width, wallpaper.details.height] == expected.size)
        #expect(wallpaper.details.frameRate == expected.frameRate)
        #expect(abs(wallpaper.details.duration - Double(expected.frames) / expected.frameRate) < 0.001)
        #expect(wallpaper.details.byteCount > 0)
        #expect(wallpaper.importedAt == ImportBench.importedAt)
        #expect(wallpaper.volume == 0)

        // The poster is the picture's size. The hover preview is small, slow, silent, and loops too.
        let poster = try picture(at: bench.location.url(for: wallpaper.poster))
        #expect(poster.size == expected.size)
        let hoverPreview = bench.location.url(for: try #require(wallpaper.hoverPreview))
        let hover = try await probeSource(at: hoverPreview)
        #expect(hover.audio == nil)
        #expect((hover.video?.nominalFrameRate ?? 99) <= 15)
        #expect(max(hover.video?.width ?? 9999, hover.video?.height ?? 9999) <= 480)
        #expect(try await validateLoopSeam(of: hoverPreview).passes)

        // Committed: in the manifest on disk, in its own folder, and nothing anywhere else.
        #expect(try bench.savedLibrary()[wallpaper.id] == wallpaper)
        #expect(bench.names(in: optimisedCopy.deletingLastPathComponent()) == ["hover.mov", "poster.heic", "wallpaper.mov"])
        #expect(bench.stagingResidue.isEmpty)
    }

    // MARK: The corpus

    static let readable: [Row<String, Expected>] = [
        Row("already what the library keeps: copied, not encoded again", "plain-h264.mp4", .kept()),
        Row("audio longer than video: kept as it is, the audio trimmed", "long-audio.mp4", .kept(hasAudio: true)),
        Row("B-frames with a start offset and an edit list", "bframes-edit-list.mp4", .transcoded()),
        Row("the same with audio longer than the video: the audio trimmed", "bframes-long-audio.mp4", .transcoded(hasAudio: true)),
        Row("variable frame rate: constant again, the dropped frames held", "variable-rate.mp4", .transcoded()),
        Row("HDR: tone-mapped to SDR", "hdr-hlg.mov", .transcoded()),
        Row("shot sideways: the picture turned upright", "rotated.mov", .transcoded(size: [180, 320])),
    ]

    @Test(arguments: readable)
    func `imports a file AVFoundation can open`(row: Row<String, Expected>) async throws {
        let candidate = ImportCandidate(source: try Fixture.url(row.input), name: "Fixture")

        try await importAndCheck(candidate, with: bench.importer(), against: row.expected)
    }

    static let converted: [Row<String, Expected>] = [
        Row("WebM", "vp9-opus.webm", .converted(hasAudio: true)),
        Row("MKV", "h264.mkv", .converted()),
        // ffmpeg fills the gap at the start of these two with one more frame.
        Row("AVI", "mpeg4-mp3.avi", .converted(hasAudio: true, frames: 61)),
        Row("WMV", "wmv2.wmv", .converted(hasAudio: true, frames: 61)),
        Row("GIF", "animation.gif", .converted(size: [160, 90], frameRate: 10, frames: 20)),
    ]

    @Test(.enabled(if: Helper.shouldRun), arguments: converted)
    func `imports a file only ffmpeg can open`(row: Row<String, Expected>) async throws {
        let candidate = ImportCandidate(source: try Fixture.url(row.input), name: "Fixture")

        try await importAndCheck(candidate, with: bench.importer(ffmpeg: Helper.required()), against: row.expected)
    }

    @Test(.enabled(if: Helper.shouldRun))
    func `imports a Wallpaper Engine folder under the project's title`() async throws {
        let item = bench.home.folder("431960/2857123456")
        try bench.home.write(#"{"file": "rain.webm", "title": "Rainy Night", "type": "video"}"#, to: "431960/2857123456/project.json")
        try FileManager.default.copyItem(at: Fixture.url("vp9-opus.webm"), to: item.appending(path: "rain.webm"))

        let candidate = try #require(try discoverSources(at: item).candidates.first)

        try await importAndCheck(candidate, with: bench.importer(ffmpeg: Helper.required()), against: .converted(hasAudio: true))
        #expect(try bench.savedLibrary().wallpapers.map(\.name) == ["Rainy Night"])
    }

    @Test func `the poster skips a black lead-in`() async throws {
        let outcome = try await bench.importer().run(ImportCandidate(source: Fixture.url("black-lead-in.mp4"), name: "Fade in"))

        guard case .imported(let wallpaper, _) = outcome else {
            Issue.record("not imported: \(outcome)")
            return
        }
        // testsrc2 is a bright test card. The second of black before it averages 16.
        #expect(try picture(at: bench.location.url(for: wallpaper.poster)).brightness > 60)
    }

    @Test func `an H.264 file that has to be transcoded comes out no larger than it went in`() async throws {
        let source = try Fixture.url("bframes-low-rate.mp4")

        let outcome = try await bench.importer().run(ImportCandidate(source: source, name: "Low rate"))

        guard case .imported(let wallpaper, let report) = outcome else {
            Issue.record("not imported: \(outcome)")
            return
        }
        #expect(report.writtenBy == .transcode)
        let copy = try await videoBitRate(of: bench.location.url(for: wallpaper.optimisedCopy))
        let original = try await videoBitRate(of: source)
        #expect(copy <= original, "the copy's video runs at \(Int(copy)) bit/s, the source's at \(Int(original))")
    }

    // MARK: Ends before anything is written

    @Test func `the same bytes under another name are a duplicate, and nothing is converted`() async throws {
        let importer = bench.importer()
        let copy = bench.home.file("Downloads/Holiday (copy 2).mov")
        try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Fixture.url("plain-h264.mp4"), to: copy)
        let holiday = ImportCandidate(source: try Fixture.url("plain-h264.mp4"), name: "Holiday")
        guard case .imported(let first, _) = try await importer.run(holiday) else {
            Issue.record("the first import failed")
            return
        }
        let stages = Recorder<ImportStage>()

        let outcome = try await importer.run(ImportCandidate(source: copy, name: "Holiday again")) { stages.append($0.stage) }

        #expect(outcome == .duplicate(of: first))
        #expect(stages.values == [.fingerprint])
        #expect(bench.wallpaperFolders == [first.id.description])
        #expect(bench.stagingResidue.isEmpty)
    }

    @Test func `a file already in the library is found by its fingerprint before its turn, and nothing is written`() async throws {
        let importer = bench.importer()
        let copy = bench.home.file("Downloads/Holiday (copy 2).mov")
        try FileManager.default.createDirectory(at: copy.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: Fixture.url("plain-h264.mp4"), to: copy)
        let holiday = ImportCandidate(source: try Fixture.url("plain-h264.mp4"), name: "Holiday")
        guard case .imported(let first, _) = try await importer.run(holiday) else {
            Issue.record("the first import failed")
            return
        }

        let again = try await importer.existingWallpaper(for: ImportCandidate(source: copy, name: "Holiday again"))
        let other = try await importer.existingWallpaper(for: ImportCandidate(source: try Fixture.url("rotated.mov"), name: "Turned"))

        #expect(again == first)
        #expect(other == nil, "a file the library does not have")
        #expect(bench.wallpaperFolders == [first.id.description])
        #expect(bench.stagingResidue.isEmpty)
        #expect(try bench.savedLibrary().wallpapers == [first])
    }

    @Test func `a file that is no video is rejected with a reason, and leaves nothing`() async throws {
        let file = try bench.home.write("Just some text, long enough to be sniffed at.", to: "holiday.mp4")

        await #expect(throws: ImportError.rejected(.unrecognised)) {
            try await bench.importer().run(ImportCandidate(source: file, name: "Holiday"))
        }
        #expect(bench.stagingResidue.isEmpty)
        #expect(bench.wallpaperFolders.isEmpty)
    }

    @Test func `a file that needs the helper, without the helper, says so`() async throws {
        await #expect(throws: ImportError.helperMissing) {
            try await bench.importer(ffmpeg: nil).run(ImportCandidate(source: Fixture.url("vp9-opus.webm"), name: "Rain"))
        }
        #expect(bench.stagingResidue.isEmpty)
    }

    // MARK: Progress

    @Test func `the import is a stream of progress that ends with the outcome`() async throws {
        var stages: [ImportStage] = []
        var fractions: [Double] = []
        var outcome: ImportOutcome?
        let candidate = ImportCandidate(source: try Fixture.url("plain-h264.mp4"), name: "Holiday")
        for try await event in bench.importer().events(importing: candidate) {
            switch event {
            case .progress(let progress):
                if stages.last != progress.stage { stages.append(progress.stage) }
                if progress.stage == .normalise, let fraction = progress.fraction { fractions.append(fraction) }
            case .finished(let finished):
                outcome = finished
            }
        }

        #expect(stages == [.fingerprint, .probe, .normalise, .validate, .artefacts, .commit])
        #expect(fractions.first == 0)
        #expect(fractions == fractions.sorted())
        #expect((fractions.last ?? 0) > 0.9)
        #expect(try bench.savedLibrary().wallpapers.map(\.name) == ["Holiday"])
        guard case .imported = outcome else {
            Issue.record("the stream ended without an outcome")
            return
        }
    }

    // MARK: A copy that fails the validator

    struct Attempt: Sendable {
        var passes: Bool
        var transcodesSoFar: Int

        var report: LoopSeamReport {
            judgeLoopSeam(passes ? LoopSeamJudgementTests.clean() : LoopSeamJudgementTests.changed { $0.hasEditList = true })
        }
    }

    static let attempts: [Row<Attempt, SeamVerdict>] = [
        Row("a clean copy is kept", Attempt(passes: true, transcodesSoFar: 0), .keep),
        Row("a clean copy is kept after a second try too", Attempt(passes: true, transcodesSoFar: 1), .keep),
        Row("a failure sends the file back through transcode", Attempt(passes: false, transcodesSoFar: 0), .transcodeAgain),
        Row("but only once", Attempt(passes: false, transcodesSoFar: 1), .reject),
    ]

    @Test(arguments: attempts)
    func `a copy that fails the validator is transcoded once more, then rejected`(row: Row<Attempt, SeamVerdict>) {
        #expect(judgeAttempt(row.input.report, transcodesSoFar: row.input.transcodesSoFar) == row.expected)
    }

    /// A validator that finds a seam in the first so many copies it is shown, then reads the rest for real.
    func importer(failingTheFirst failures: Int, validations: Recorder<String>) -> Importer {
        Importer(location: bench.location, library: bench.library, ffmpeg: nil, shaderTools: nil, validate: { copy in
            validations.append(copy.lastPathComponent)
            let isOptimisedCopy = copy.lastPathComponent == "wallpaper.mov"
            let seen = validations.values.count { $0 == "wallpaper.mov" }
            if isOptimisedCopy, seen <= failures { return Attempt(passes: false, transcodesSoFar: 0).report }
            return try await validateLoopSeam(of: copy)
        })
    }

    @Test func `a remux that fails the validator is transcoded, and that copy is the one kept`() async throws {
        let validations = Recorder<String>()
        let candidate = ImportCandidate(source: try Fixture.url("plain-h264.mp4"), name: "Holiday")

        let outcome = try await importer(failingTheFirst: 1, validations: validations).run(candidate)

        guard case .imported(let wallpaper, let report) = outcome else {
            Issue.record("not imported: \(outcome)")
            return
        }
        #expect(report.plan == .remux)
        #expect(report.writtenBy == .transcode)
        #expect(wallpaper.details.codec == "hevc")
        #expect(validations.values == ["wallpaper.mov", "wallpaper.mov", "hover.mov"])
        #expect(try await validateLoopSeam(of: bench.location.url(for: wallpaper.optimisedCopy)).passes)
    }

    @Test func `a file that fails again after the transcode is rejected with the report, and leaves nothing`() async throws {
        let validations = Recorder<String>()
        let candidate = ImportCandidate(source: try Fixture.url("plain-h264.mp4"), name: "Holiday")

        await #expect(throws: ImportError.loopSeam(Attempt(passes: false, transcodesSoFar: 0).report)) {
            try await importer(failingTheFirst: 2, validations: validations).run(candidate)
        }
        #expect(validations.values == ["wallpaper.mov", "wallpaper.mov"])
        #expect(bench.stagingResidue.isEmpty)
        #expect(bench.wallpaperFolders.isEmpty)
        #expect(try bench.savedLibrary().wallpapers.isEmpty)
    }
}
