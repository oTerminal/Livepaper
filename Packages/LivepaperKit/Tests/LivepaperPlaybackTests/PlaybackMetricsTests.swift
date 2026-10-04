import Foundation
import Testing
@testable import LivepaperPlayback

// The soak's parser and the release checklist read this line: a change of wording here
// is a change there too.
struct PlaybackMetricsTests {
    private static let surface = SurfaceID(uuid: UUID(uuidString: "DBB685F7-0000-0000-0000-000000000001") ?? UUID())

    @Test func `the metrics line keeps its wording`() {
        let metrics = PlaybackMetrics(
            video: "AAAAAAAA-0000-0000-0000-000000000001/wallpaper.mov",
            loops: 200,
            seamsWatched: 199,
            largestSeamStep: 1,
            largestInLoopStep: 1,
            largestPresentedGap: 1.32,
            largestPresentedGapAtSeam: 1.11,
            gapsOverLimitAtSeams: 0,
            gapsOverLimitElsewhere: 1,
            droppedFrames: 2,
            totalFrames: 30000,
            smallestSeamLead: 0.4512,
            flushes: 0,
            failures: 0,
            markerBuffersSkipped: 800,
            nextReaderMisses: 0
        )

        #expect(
            metrics.logLine(for: .surface(Self.surface))
                == "playback metrics for surface DBB685F7-0000-0000-0000-000000000001 on "
                + "AAAAAAAA-0000-0000-0000-000000000001/wallpaper.mov: loops 200, seams watched 199, "
                + "seam step 1.00, in-loop step 1.00, presented gap 1.32, at a seam 1.11, "
                + "gaps over 1.5 at seams 0, elsewhere 1, renderer dropped 2 of 30000, seam lead 0.45 s, "
                + "flushes 0, failures 0, markers skipped 800, next-reader misses 0"
        )
    }

    @Test func `numbers not measured yet read none`() {
        let metrics = PlaybackMetrics(video: "clip.mov")

        #expect(
            metrics.logLine(for: .preview)
                == "playback metrics for preview on clip.mov: loops 0, seams watched 0, "
                + "seam step none, in-loop step none, presented gap none, at a seam none, "
                + "gaps over 1.5 at seams 0, elsewhere 0, renderer dropped none of none, seam lead none s, "
                + "flushes 0, failures 0, markers skipped 0, next-reader misses 0"
        )
    }
}
