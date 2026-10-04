import Foundation
import Testing
import LivepaperCore
import LivepaperImport

/// Every word the import list and its toasts show, pinned. They are the product's vocabulary: Optimising, never Transcoding.
struct ImportWordsTests {
    static let stages: [Row<ImportStage, String>] = [
        Row("the fingerprint looks for the file in the library", .fingerprint, "Checking"),
        Row("the probe", .probe, "Reading"),
        Row("the ffmpeg helper", .convert, "Converting"),
        Row("writing the optimised copy", .normalise, "Optimising"),
        Row("the loop-seam validator", .validate, "Checking the loop"),
        Row("a scene's files, and the renderer's own work on them", .prepare, "Preparing the scene"),
        Row("the poster and the hover preview", .artefacts, "Making the poster"),
        Row("the commit", .commit, "Finishing"),
    ]

    @Test func `every stage has its words`() {
        #expect(Self.stages.map(\.input) == ImportStage.allCases)
    }

    @Test(arguments: stages)
    func `says what stage an import is at`(row: Row<ImportStage, String>) {
        #expect(stageWords(row.input) == row.expected)
    }

    struct Words: Equatable, Sendable {
        var reason: String
        var canRetry: Bool

        /// The same file would fail the same way again.
        static func final(_ reason: String) -> Words { Words(reason: reason, canRetry: false) }
        /// Something outside the file, which may be different next time.
        static func retryable(_ reason: String) -> Words { Words(reason: reason, canRetry: true) }
    }

    struct Unforeseen: Error {}

    static let seamReport = judgeLoopSeam(TrackReading(timescale: 600, frames: [], trackDuration: 0, hasEditList: false))

    static let failures: [Row<any Error, Words>] = [
        Row("not a kind of file it reads", ImportError.rejected(.unrecognised), .final("It is not a kind of file Livepaper can read")),
        Row("audio only", ImportError.rejected(.noVideo), .final("It has no picture to play")),
        Row("a video track with nothing in it", ImportError.rejected(.noFrames), .final("It has no frames to play")),
        Row("copy-protected", ImportError.rejected(.protected), .final("It is copy-protected")),
        Row(
            "a format that needs the helper, and no helper",
            ImportError.helperMissing,
            .final("Its format needs the ffmpeg helper, which is missing")
        ),
        Row(
            "the helper made something AVFoundation cannot read",
            ImportError.helperOutputUnreadable,
            .final("The ffmpeg helper converted it, but Livepaper cannot read the result")
        ),
        Row("still a seam after the second try", ImportError.loopSeam(seamReport), .final("It would not loop without a gap")),
        Row(
            "a scene's package that is not one",
            ImportError.scene(.notAPackage),
            .final("Its Wallpaper Engine scene package cannot be read")
        ),
        Row(
            "a scene that is not in its package",
            ImportError.scene(.missingEntry("scene.json")),
            .final("Its Wallpaper Engine scene cannot be read")
        ),
        Row("a scene's JSON nobody could read", ImportError.scene(.malformedScene), .final("Its Wallpaper Engine scene cannot be read")),
        Row(
            "a scene with no size of its own",
            ImportError.sceneWithoutSize,
            .final("Its Wallpaper Engine scene has no fixed size, which Livepaper needs to show it")
        ),

        Row("no video track, found late", MediaError.noVideoTrack, .final("It has no picture to play")),
        Row("a read that failed: its drive may have gone", MediaError.readFailed("unknown"), .retryable("It could not be read")),
        Row("a write that failed: the disk may be full", MediaError.writeFailed(""), .retryable("Its optimised copy could not be written")),

        Row("the helper would not start", FFmpegError.launchFailed(""), .retryable("The ffmpeg helper could not be started")),
        Row("the helper gave up on the file", FFmpegError.failed(status: 1, message: ""), .final("The ffmpeg helper could not convert it")),
        Row("the helper ran out of time", FFmpegError.timeLimitExceeded, .final("Converting it took too long")),
        Row("the helper's output grew past the limit", FFmpegError.sizeLimitExceeded, .final("It would be too large once converted")),

        Row("not one picture could be taken for the poster", ArtefactError.noPicture, .final("It has no picture to make a poster from")),
        Row("the poster could not be saved", ArtefactError.posterNotWritten, .retryable("Its poster could not be written")),

        Row(
            "a scene's file that has come to lead out of its folder since discovery",
            WallpaperEngineProjectError.escapesFolder("scene.pkg"),
            .final("Its Wallpaper Engine project names a file outside its folder")
        ),
        Row(
            "gone since it was dropped",
            DiscoverError.notFound(URL(filePath: "/Volumes/Archive/Harbour.mov")),
            .retryable("It could not be found")
        ),
        Row("gone, as opening it reports", CocoaError(.fileNoSuchFile), .retryable("It could not be found")),
        Row("gone, as reading it reports", CocoaError(.fileReadNoSuchFile), .retryable("It could not be found")),
        Row("the library's disk is full", CocoaError(.fileWriteOutOfSpace), .retryable("There is not enough disk space")),
        Row("anything else", Unforeseen(), .retryable("It could not be imported")),
    ]

    @Test(arguments: failures)
    func `says why an import failed, and whether Retry can help`(row: Row<any Error, Words>) {
        let words = importFailureWords(row.input)

        #expect(Words(reason: words.reason, canRetry: words.canRetry) == row.expected)
    }

    static let skips: [Row<SkipReason, String>] = [
        Row(
            "a web item",
            .wallpaperEngine(.runsCode("web")),
            "It is a web page for Wallpaper Engine, which runs code of its own; only video and scene items can be imported"
        ),
        Row(
            "an application",
            .wallpaperEngine(.runsCode("application")),
            "It is an application for Wallpaper Engine, which runs code of its own; only video and scene items can be imported"
        ),
        Row(
            "a type nobody knows, which is not repeated back",
            .wallpaperEngine(.unsupportedType("preset")),
            "Only Wallpaper Engine video and scene items can be imported"
        ),
        Row(
            "a scene whose files lie loose",
            .noScenePackage("scene.pkg"),
            "Its Wallpaper Engine scene has no “scene.pkg” in its folder"
        ),
        Row("a project.json nobody could read", .wallpaperEngine(.malformed), "Its Wallpaper Engine project cannot be read"),
        Row("a video item that names no file", .wallpaperEngine(.noFile), "Its Wallpaper Engine project names no file"),
        Row(
            "a file outside the item's folder, which is not repeated back",
            .wallpaperEngine(.escapesFolder("../../etc/passwd")),
            "Its Wallpaper Engine project names a file outside its folder"
        ),
        Row(
            "a file the project names and the folder lacks",
            .missingFile("rain.mp4"),
            "Its Wallpaper Engine project names “rain.mp4”, which is not in its folder"
        ),
    ]

    @Test(arguments: skips)
    func `says why a source was skipped`(row: Row<SkipReason, String>) {
        #expect(skipWords(row.input) == row.expected)
    }

    // MARK: Toasts

    static let toasts: [Row<ImportToast, ImportToast>] = [
        Row(
            "a duplicate names the wallpaper it already is",
            .duplicate(of: .numbered(1)),
            ImportToast(kind: .alreadyThere, words: "Already in the library as “Harbour 1”")
        ),
        Row(
            "a file dropped again while its row is on the list",
            .alreadyListed(name: "Harbour 1"),
            ImportToast(kind: .alreadyThere, words: "“Harbour 1” is already in the import list")
        ),
        Row(
            "a skipped source is named as it was dropped, and says why",
            .skipped(SkippedSource(
                url: URL(filePath: "/Users/tester/Workshop/2345678901"), reason: .wallpaperEngine(.runsCode("web"))
            )),
            ImportToast(
                kind: .notImported,
                words: "“2345678901” was not imported. It is a web page for Wallpaper Engine, which runs code of its own; "
                    + "only video and scene items can be imported."
            )
        ),
        Row(
            "a failure names the file and says why",
            .failed(name: "Harbour 1", error: ImportError.rejected(.protected)),
            ImportToast(kind: .notImported, words: "“Harbour 1” was not imported. It is copy-protected.")
        ),
    ]

    @Test(arguments: toasts)
    func `each toast says what happened to the file`(row: Row<ImportToast, ImportToast>) {
        #expect(row.input == row.expected)
    }

    @Test func `a source file that has gone is found out as the importer finds it out`() async throws {
        let gone = URL(filePath: "/Volumes/Archive/Harbour.mov")
        let error = await #expect(throws: (any Error).self) { try await fingerprint(of: gone) }

        #expect(importFailureWords(try #require(error)) == ("It could not be found", true))
    }
}
