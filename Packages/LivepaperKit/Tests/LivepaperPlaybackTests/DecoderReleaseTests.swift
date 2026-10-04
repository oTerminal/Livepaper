import CoreMedia
import Foundation
import Testing
@testable import LivepaperPlayback

struct DecoderReleaseTests {
    static let halts: [Row<Halt, Halt.Kept>] = [
        Row("a pause keeps the decoder and the picture", .pause, Halt.Kept(decoder: true, picture: true)),
        Row("a suspend gives the decoder back and keeps the picture", .suspend, Halt.Kept(decoder: false, picture: true)),
        Row("a stop gives the decoder back and takes the picture off", .stop, Halt.Kept(decoder: false, picture: false)),
    ]

    @Test(arguments: halts)
    func `what stopping keeps`(row: Row<Halt, Halt.Kept>) {
        #expect(row.input.keeps == row.expected)
    }

    // MARK: The layer's decoder

    @Test func `a layer that never played has no decoder to give back`() {
        let decoder = LayerDecoder()

        #expect(decoder.release() == nil)
    }

    @Test func `a layer gives back the decoder its video made, once`() throws {
        let decoder = LayerDecoder()
        let video = try videoFormat(width: 1920, height: 1080)

        decoder.fed(video)

        #expect(decoder.release() == video)
        #expect(decoder.release() == nil)
    }

    @Test func `the decoder given back is the one the latest start made`() throws {
        let decoder = LayerDecoder()
        let first = try videoFormat(width: 1920, height: 1080)
        let second = try videoFormat(width: 3840, height: 2160)

        decoder.fed(first)
        decoder.fed(second)

        #expect(decoder.release() == second)
    }

    @Test func `a start after a release holds a decoder again`() throws {
        let decoder = LayerDecoder()
        let video = try videoFormat(width: 1920, height: 1080)

        decoder.fed(video)
        _ = decoder.release()
        decoder.fed(video)

        #expect(decoder.release() == video)
    }

    @Test func `what is not a video makes no decoder`() throws {
        let decoder = LayerDecoder()
        var audio: CMAudioFormatDescription?
        var description = AudioStreamBasicDescription(
            mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM, mFormatFlags: kAudioFormatFlagIsFloat,
            mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 1, mBitsPerChannel: 32, mReserved: 0
        )
        let status = CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &audio
        )
        try #require(status == noErr)
        guard let audio else { return }

        decoder.fed(audio)
        decoder.fed(nil)

        #expect(decoder.release() == nil)
    }

    // MARK: The release frame

    @Test func `the release frame is a JPEG, the size of the video`() throws {
        let video = try videoFormat(width: 1920, height: 1080)

        let frame = try #require(releaseFrame(shapedLike: video, at: CMTime(value: 7, timescale: 30)))
        let format = try #require(frame.formatDescription)

        #expect(format.mediaSubType == .jpeg)
        #expect(format.dimensions.width == 1920)
        #expect(format.dimensions.height == 1080)
        #expect(frame.presentationTimeStamp == CMTime(value: 7, timescale: 30))
    }

    @Test func `the release frame is decoded and never shown`() throws {
        let frame = try #require(releaseFrame(shapedLike: try videoFormat(width: 1920, height: 1080), at: .zero))
        let attachments = try #require(frame.sampleAttachments.first)

        #expect(attachments[.doNotDisplay] as? Bool == true)
        #expect(attachments[.displayImmediately] == nil)
    }

    @Test func `the release frame carries a small JPEG, whatever the size of the video`() throws {
        let frame = try #require(releaseFrame(shapedLike: try videoFormat(width: 3840, height: 2160), at: .zero))
        let data = try #require(frame.dataBuffer)
        let bytes = try data.dataBytes()

        #expect(frame.numSamples == 1)
        #expect(bytes.count < 2048)
        #expect(bytes.prefix(2) == Data([0xFF, 0xD8]))
    }

    @Test func `the release frame keeps the video's clean aperture and pixel aspect ratio`() throws {
        let aperture: [CFString: Any] = [
            kCMFormatDescriptionKey_CleanApertureWidth: 1912,
            kCMFormatDescriptionKey_CleanApertureHeight: 1072,
            kCMFormatDescriptionKey_CleanApertureHorizontalOffset: 0,
            kCMFormatDescriptionKey_CleanApertureVerticalOffset: 0,
        ]
        let aspect: [CFString: Any] = [
            kCMFormatDescriptionKey_PixelAspectRatioHorizontalSpacing: 4,
            kCMFormatDescriptionKey_PixelAspectRatioVerticalSpacing: 3,
        ]
        let video = try videoFormat(width: 1920, height: 1080, extensions: [
            kCMFormatDescriptionExtension_CleanAperture: aperture,
            kCMFormatDescriptionExtension_PixelAspectRatio: aspect,
        ])

        let frame = try #require(releaseFrame(shapedLike: video, at: .zero))
        let format = try #require(frame.formatDescription)

        #expect(
            format.presentationDimensions(usePixelAspectRatio: true, useCleanAperture: true)
                == video.presentationDimensions(usePixelAspectRatio: true, useCleanAperture: true)
        )
    }
}

private func videoFormat(width: Int32, height: Int32, extensions: [CFString: Any]? = nil) throws -> CMVideoFormatDescription {
    var format: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreate(
        allocator: nil, codecType: kCMVideoCodecType_HEVC, width: width, height: height,
        extensions: extensions as CFDictionary?, formatDescriptionOut: &format
    )
    return try #require(format)
}
