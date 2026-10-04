import Foundation
import Testing
import LivepaperImport

struct ImportPlanTests {
    // One row per combination that changes the answer.
    static let rows: [Row<ProbeResult, ImportPlan>] = [
        Row("H.264, SDR, constant rate, clean timing: kept as it is", .isoMedia(), .remux),
        Row("HEVC likewise", .isoMedia { $0.codec = "hvc1" }, .remux),
        Row(
            "an audio track longer than the video is no reason to transcode: the remux trims it",
            ProbeResult(container: .isoMedia, isReadable: true, video: .clean(), audio: AudioProbe(codec: "aac ", duration: 5.4)),
            .remux
        ),
        Row("a track longer than its frames is put right by the remux", .isoMedia { $0.duration = 5.02 }, .remux),

        Row("ProRes is accepted, not kept", .isoMedia { $0.codec = "apch" }, .transcode),
        Row("HLG is tone-mapped", .isoMedia { $0.transferFunction = .hlg }, .transcode),
        Row("PQ is tone-mapped", .isoMedia { $0.codec = "hvc1"; $0.transferFunction = .pq }, .transcode),
        Row("a variable frame rate is made constant", .isoMedia { $0.timing = .variable }, .transcode),
        Row("an edit list that retimes is played out", .isoMedia { $0.hasEditList = true }, .transcode),
        Row("reordered frames cannot start at zero without an edit list", .isoMedia { $0.hasFrameReordering = true }, .transcode),
        Row("a first frame that is not a sync sample", .isoMedia { $0.startsOnSyncFrame = false }, .transcode),
        Row("a track shot sideways: the engine shows samples as they are", .isoMedia { $0.orientation = .turned(degrees: 90) }, .transcode),
        Row("a mirrored track likewise", .isoMedia { $0.orientation = .transformed }, .transcode),

        Row("a codec AVFoundation cannot decode, in a container it can open", .isoMedia { $0.isDecodable = false }, .ffmpeg),
        Row("an MP4 AVFoundation cannot open goes to ffmpeg", ProbeResult(container: .isoMedia, isReadable: false), .ffmpeg),
        Row("WebM", ProbeResult(container: .webm, isReadable: false), .ffmpeg),
        Row("MKV", ProbeResult(container: .matroska, isReadable: false), .ffmpeg),
        Row("AVI", ProbeResult(container: .avi, isReadable: false), .ffmpeg),
        Row("WMV", ProbeResult(container: .asf, isReadable: false), .ffmpeg),
        Row("GIF", ProbeResult(container: .gif, isReadable: false), .ffmpeg),

        Row("not a kind of file Livepaper reads", ProbeResult(container: nil, isReadable: false), .reject(.unrecognised)),
        Row(
            "audio only",
            ProbeResult(container: .isoMedia, isReadable: true, audio: AudioProbe(codec: "aac ", duration: 5)),
            .reject(.noVideo)
        ),
        Row("a video track with nothing in it", .isoMedia { $0.frameCount = 0 }, .reject(.noFrames)),
        Row(
            "a protected film, even a clean one",
            ProbeResult(container: .isoMedia, isReadable: true, isProtected: true, video: .clean()),
            .reject(.protected)
        ),
    ]

    @Test(arguments: rows)
    func `plans the conversion from the probe alone`(row: Row<ProbeResult, ImportPlan>) {
        #expect(planImport(row.input) == row.expected)
    }
}
