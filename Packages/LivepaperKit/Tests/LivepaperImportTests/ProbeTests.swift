import Foundation
import Testing
import LivepaperImport

/// The probe on the fixture corpus. What the files are is written in `Fixtures/make-fixtures.sh`.
struct ProbeTests {
    @Test func `a plain H.264 file: everything the planner asks about`() async throws {
        let probe = try await probeSource(at: Fixture.url("plain-h264.mp4"))

        #expect(probe == ProbeResult(
            container: .isoMedia,
            isReadable: true,
            video: VideoProbe(
                codec: "avc1", isDecodable: true, width: 320, height: 180, orientation: .upright, nominalFrameRate: 30,
                minFrameDuration: 512.0 / 15360, timing: .constant(FrameRate(duration: 512, timescale: 15360)), frameCount: 60, duration: 2,
                bitRate: 311_756, hasEditList: false, hasFrameReordering: false, startsOnSyncFrame: true, transferFunction: .sdr
            )
        ))
        #expect(planImport(probe) == .remux)
    }

    @Test func `the duration of each track: an audio track longer than the video`() async throws {
        let probe = try await probeSource(at: Fixture.url("long-audio.mp4"))

        #expect(probe.video?.duration == 2)
        #expect(probe.audio == AudioProbe(codec: "aac ", duration: 2.4))
        #expect(planImport(probe) == .remux)
    }

    @Test func `reordered frames and ffmpeg's edit list`() async throws {
        let video = try #require(try await probeSource(at: Fixture.url("bframes-edit-list.mp4")).video)

        #expect(video.hasEditList)
        #expect(video.hasFrameReordering)
        #expect(video.timing == .constant(FrameRate(duration: 512, timescale: 15360)))
    }

    @Test func `a variable frame rate`() async throws {
        let video = try #require(try await probeSource(at: Fixture.url("variable-rate.mp4")).video)

        #expect(video.timing == .variable)
        #expect(video.frameCount == 50)
        #expect(video.minFrameDuration == 512.0 / 15360)
    }

    @Test func `HDR is known by its transfer function`() async throws {
        let video = try #require(try await probeSource(at: Fixture.url("hdr-hlg.mov")).video)

        #expect(video.codec == "hvc1")
        #expect(video.transferFunction == .hlg)
    }

    @Test func `a track shot sideways`() async throws {
        let video = try #require(try await probeSource(at: Fixture.url("rotated.mov")).video)

        #expect(video.orientation == .turned(degrees: 270))
        #expect((video.width, video.height) == (320, 180))
    }

    static let unreadable: [Row<String, Container>] = [
        Row("WebM", "vp9-opus.webm", .webm),
        Row("MKV", "h264.mkv", .matroska),
        Row("AVI", "mpeg4-mp3.avi", .avi),
        Row("WMV", "wmv2.wmv", .asf),
        Row("GIF", "animation.gif", .gif),
    ]

    @Test(arguments: unreadable)
    func `a container AVFoundation cannot open is known by its bytes and left to ffmpeg`(row: Row<String, Container>) async throws {
        let probe = try await probeSource(at: Fixture.url(row.input))

        #expect(probe == ProbeResult(container: row.expected, isReadable: false))
        #expect(planImport(probe) == .ffmpeg)
    }

    @Test func `a file that is no video at all, whatever it is called`() async throws {
        let folder = try TemporaryFolder()
        let file = try folder.write("Just some text, long enough to be sniffed at.", to: "holiday.mp4")

        let probe = try await probeSource(at: file)

        #expect(probe == ProbeResult(container: nil, isReadable: false))
    }
}
