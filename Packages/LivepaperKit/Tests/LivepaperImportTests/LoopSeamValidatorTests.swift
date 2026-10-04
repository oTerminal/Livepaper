import Foundation
import Testing
import LivepaperImport

/// The validator on source files as they come: it has to tell the ones that
/// would stall at the seam from the one that would not.
struct LoopSeamValidatorTests {
    @Test func `a clean file passes, read as the engine reads it`() async throws {
        let report = try await validateLoopSeam(of: Fixture.url("plain-h264.mp4"))

        #expect(report.passes, "\(report)")
        // 60 frames of 512 ticks at 1/15360: the marker buffers are not frames.
        #expect(report.frameCount == 60)
        #expect(report.timescale == 15360)
        #expect(report.frameDuration == 512)
        #expect(report.endOfLastFrame == 30720)
        #expect(report.seamStep == 512)
    }

    static let broken: [Row<String, [LoopSeamFailure]>] = [
        Row(
            "ffmpeg's B-frame edit list: first frame two frames in, in media time",
            "bframes-edit-list.mp4",
            [.firstFrameNotAtZero, .trackDurationNotEndOfLastFrame, .editList]
        ),
        Row("a variable frame rate", "variable-rate.mp4", [.unevenFrames]),
    ]

    @Test(arguments: broken)
    func `a file that would stall at the seam fails, and the report says why`(row: Row<String, [LoopSeamFailure]>) async throws {
        let report = try await validateLoopSeam(of: Fixture.url(row.input))

        #expect(report.failures == row.expected, "\(report)")
    }

    @Test func `a file with no video track cannot be validated`() async throws {
        await #expect(throws: MediaError.noVideoTrack) {
            try await validateLoopSeam(of: Fixture.url("vp9-opus.webm"))
        }
    }
}
