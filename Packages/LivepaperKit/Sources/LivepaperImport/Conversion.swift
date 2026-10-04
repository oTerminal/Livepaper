import AVFoundation
import CoreMedia
import Foundation
import Synchronization
import VideoToolbox

/// What a transcode is asked to make.
struct Rendition: Sendable {
    var rate: FrameRate
    /// The longer side, in pixels. Nil keeps the picture's size.
    var maxDimension: Int?
    var includesAudio: Bool
    var spending: Spending

    /// What the encoder is told to spend. VideoToolbox takes one or the other:
    /// given a quality, it ignores an average rate.
    enum Spending: Sendable {
        /// 0 to 1: the same quality throughout, at whatever rate that takes.
        case quality(Double)
        /// Bits per second, over the whole file.
        case averageBitRate(Int)
    }

    static func optimisedCopy(rate: FrameRate, spending: Spending) -> Rendition {
        Rendition(rate: rate, maxDimension: nil, includesAudio: true, spending: spending)
    }

    /// Small, low rate, no audio.
    static func hoverPreview(of rate: FrameRate) -> Rendition {
        Rendition(rate: rate.reduced(toAtMost: 15), maxDimension: 480, includesAudio: false, spending: .quality(0.5))
    }

    /// HEVC, SDR, and nothing in the stream that would need an edit list to play from zero.
    func encoderSettings(size: (width: Int, height: Int), for writer: AVAssetWriter) -> [String: Any] {
        var compression: [String: Any] = [
            // No B-frames: reordered frames cannot be written with the first at zero and no edit list.
            AVVideoAllowFrameReorderingKey: false,
            AVVideoMaxKeyFrameIntervalDurationKey: 2,
        ]
        switch spending {
        case .quality(let quality): compression[AVVideoQualityKey] = quality
        case .averageBitRate(let bitRate): compression[AVVideoAverageBitRateKey] = bitRate
        }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.hevc,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
            AVVideoColorPropertiesKey: [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2,
            ],
            AVVideoCompressionPropertiesKey: compression,
        ]
        guard case .averageBitRate = spending else { return settings }
        // Without look-ahead the rate control starts starved: the first two seconds, the start of
        // every loop, come out soft. Any count turns it on. The software encoder has none, and
        // AVFoundation throws on settings the encoder cannot take rather than leave them out.
        compression[kVTCompressionPropertyKey_SuggestedLookAheadFrameCount as String] = 48
        var withLookAhead = settings
        withLookAhead[AVVideoCompressionPropertiesKey] = compression
        return writer.canApply(outputSettings: withLookAhead, forMediaType: .video) ? withLookAhead : settings
    }
}

/// Both conversions write the same kind of file, which is what normalising means:
/// the first frame at zero and a sync sample, every frame one frame duration
/// after the one before, no edit list but the writer's own from zero to the
/// end, the track exactly as long as its frames, and the audio cut to the video.
///
/// Copies the compressed samples as they are. Only for a track the planner
/// found clean: constant rate, no reordering, a sync sample first.
@concurrent
func remux(_ source: URL, to destination: URL, rate: FrameRate, progress: @escaping @Sendable (Double) -> Void) async throws {
    let asset = AVURLAsset(url: source)
    guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw MediaError.noVideoTrack }
    let (formats, timeRange) = try await track.load(.formatDescriptions, .timeRange)
    let audio = try await AudioPlan(of: asset, within: timeRange)
    let media = Unchecked((asset: asset, track: track))

    try await onOwnThread { cancellation in
        let reader = try AVAssetReader(asset: media.value.asset)
        let output = AVAssetReaderTrackOutput(track: media.value.track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        reader.add(output)

        let job = try WritingJob(destination: destination, rate: rate, cancellation: cancellation)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: formats.first)
        try job.add(video: input)
        let audioCopy = try audio.map { try AudioCopy($0, into: job) }

        try job.start(reader, audioCopy?.reader)
        try job.run(audio: audioCopy, video: input) {
            var written: Int64 = 0
            while let buffer = output.copyNextSampleBuffer() {
                guard buffer.carriesMedia else { continue }
                // Stamped by counting, so that a tick of rounding in the source file does not survive.
                let timings = (written..<written + Int64(buffer.numSamples)).map { frame in
                    let pts = CMTime(value: frame * rate.duration, timescale: rate.timescale)
                    return CMSampleTimingInfo(duration: rate.time, presentationTimeStamp: pts, decodeTimeStamp: pts)
                }
                try job.append(try CMSampleBuffer(copying: buffer, withNewTiming: timings), to: input)
                written += Int64(timings.count)
                progress(min(1, Double(written) * rate.secondsPerFrame / max(timeRange.duration.seconds, rate.secondsPerFrame)))
            }
            guard reader.status == .completed else { throw MediaError.readFailed(describe(reader.error)) }
            return written
        }
    }
}

/// Decodes and encodes again: the picture upright, SDR, at a constant rate.
@concurrent
func transcode(_ source: URL, to destination: URL, as rendition: Rendition, progress: @escaping @Sendable (Double) -> Void) async throws {
    let asset = AVURLAsset(url: source)
    guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw MediaError.noVideoTrack }
    let timeRange = try await track.load(.timeRange)
    let audio = rendition.includesAudio ? try await AudioPlan(of: asset, within: timeRange) : nil

    // The composition turns the picture upright, plays out the edit list and tone-maps HDR to BT.709.
    var configuration = try await AVVideoComposition.Configuration(for: asset)
    configuration.colorPrimaries = AVVideoColorPrimaries_ITU_R_709_2
    configuration.colorTransferFunction = AVVideoTransferFunction_ITU_R_709_2
    configuration.colorYCbCrMatrix = AVVideoYCbCrMatrix_ITU_R_709_2
    let composition = configuration
    let size = composition.renderSize.fitted(toLongerSide: rendition.maxDimension)
    let media = Unchecked((asset: asset, track: track))

    try await onOwnThread { cancellation in
        let reader = try AVAssetReader(asset: media.value.asset)
        let output = AVAssetReaderVideoCompositionOutput(
            videoTracks: [media.value.track],
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange]
        )
        output.videoComposition = AVVideoComposition(configuration: composition)
        output.alwaysCopiesSampleData = false
        reader.add(output)

        let job = try WritingJob(destination: destination, rate: rendition.rate, cancellation: cancellation)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: rendition.encoderSettings(size: size, for: job.writer))
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
        try job.add(video: input)
        let audioCopy = try audio.map { try AudioCopy($0, into: job) }

        try job.start(reader, audioCopy?.reader)
        try job.run(audio: audioCopy, video: input) {
            var resampler = ConstantRateResampler(rate: rendition.rate)
            var written: Int64 = 0
            var held: (pixels: CVPixelBuffer, pts: Double)?

            func write(_ pixels: CVPixelBuffer, times count: Int) throws {
                for _ in 0..<count {
                    try job.waitUntilReady(input)
                    let pts = CMTime(value: written * rendition.rate.duration, timescale: rendition.rate.timescale)
                    guard adaptor.append(pixels, withPresentationTime: pts) else { throw job.writeFailure() }
                    written += 1
                }
            }

            while let buffer = output.copyNextSampleBuffer() {
                guard let pixels = buffer.imageBuffer else { continue }
                let pts = buffer.presentationTimeStamp.seconds
                if let count = resampler.next(pts: pts), let held { try write(held.pixels, times: count) }
                held = (pixels, pts)
                progress(min(1, (pts - timeRange.start.seconds) / max(timeRange.duration.seconds, rendition.rate.secondsPerFrame)))
            }
            guard reader.status == .completed else { throw MediaError.readFailed(describe(reader.error)) }
            // The last frame gets one frame's time. A track that runs on after it is the stall this is here to remove.
            if let held { try write(held.pixels, times: resampler.finish(end: held.pts + rendition.rate.secondsPerFrame)) }
            return written
        }
    }
}

// MARK: - Writing

/// One file being written: a video input, perhaps an audio input, and the
/// rules for ending it so that the track is exactly as long as its frames.
///
/// Everything here blocks, and runs on threads of its own (`onOwnThread`): the
/// caller's for the video, one more for the audio. The writer takes each
/// input's samples on whatever thread brings them.
private final class WritingJob: @unchecked Sendable {
    let writer: AVAssetWriter
    let rate: FrameRate
    private let destination: URL
    private let cancellation: Cancellation
    private var readers: [AVAssetReader] = []
    /// Set when either track fails, so that the other does not wait for ever on a writer that is going nowhere.
    private let abandoned = Atomic(false)

    /// Thrown on the track that was stopped because the other one failed. Never the error that is reported.
    private struct Abandoned: Error {}

    init(destination: URL, rate: FrameRate, cancellation: Cancellation) throws {
        self.destination = destination
        self.rate = rate
        self.cancellation = cancellation
        writer = try AVAssetWriter(outputURL: destination, fileType: .mov)
        // The movie's clock is the track's, so that the track's duration is exact and not rounded to 1/600 s.
        writer.movieTimeScale = rate.timescale
    }

    func add(video input: AVAssetWriterInput) throws {
        input.mediaTimeScale = rate.timescale
        try add(input)
    }

    func add(_ input: AVAssetWriterInput) throws {
        input.expectsMediaDataInRealTime = false
        guard writer.canAdd(input) else { throw MediaError.writeFailed("the writer does not take this input") }
        writer.add(input)
    }

    func start(_ readers: AVAssetReader?...) throws {
        self.readers = readers.compactMap(\.self)
        for reader in self.readers where !reader.startReading() {
            throw MediaError.readFailed(describe(reader.error))
        }
        guard writer.startWriting() else { throw writeFailure() }
        writer.startSession(atSourceTime: .zero)
    }

    /// Feeds the video and the audio side by side, then ends the file where
    /// the video's frames end. Whatever goes wrong, a cancel included, no file is left.
    ///
    /// `video` feeds the video input and answers how many frames it wrote.
    func run(audio: AudioCopy?, video input: AVAssetWriterInput, _ video: () throws -> Int64) throws {
        do {
            let audioDone = DispatchSemaphore(value: 0)
            let audioResult = Mutex<Result<Void, any Error>>(.success(()))
            if let audio {
                Thread.detachNewThread { [self] in
                    let result = Result { try audio.run(in: self) }
                    if case .failure = result { abandoned.store(true, ordering: .relaxed) }
                    audioResult.withLock { $0 = result }
                    audioDone.signal()
                }
            } else {
                audioDone.signal()
            }

            let videoResult = Result {
                let frames = try video()
                input.markAsFinished()
                return frames
            }
            if case .failure = videoResult { abandoned.store(true, ordering: .relaxed) }
            audioDone.wait()

            // The track that failed says why, not the one that was stopped on its account.
            let failures = [videoResult.failure, audioResult.withLock(\.failure)].compactMap(\.self)
            if let failure = failures.first(where: { !($0 is Abandoned) }) ?? failures.first { throw failure }
            let frames = try videoResult.get()
            try cancellation.check()
            guard frames > 0 else { throw MediaError.readFailed("the video track has no frames") }
            // Audio that runs past this point is cut here: the audio is trimmed to the video, never the reverse.
            writer.endSession(atSourceTime: CMTime(value: frames * rate.duration, timescale: rate.timescale))
            let finished = DispatchSemaphore(value: 0)
            writer.finishWriting { finished.signal() }
            finished.wait()
            guard writer.status == .completed else { throw writeFailure() }
        } catch {
            readers.forEach { $0.cancelReading() }
            if writer.status == .writing { writer.cancelWriting() }
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    func append(_ buffer: CMSampleBuffer, to input: AVAssetWriterInput) throws {
        try waitUntilReady(input)
        guard input.append(buffer) else { throw writeFailure() }
    }

    func waitUntilReady(_ input: AVAssetWriterInput) throws {
        while !input.isReadyForMoreMediaData {
            try checkStillWanted()
            guard writer.status == .writing else { throw writeFailure() }
            Thread.sleep(forTimeInterval: 0.002)
        }
        try checkStillWanted()
    }

    func writeFailure() -> MediaError {
        .writeFailed(describe(writer.error))
    }

    private func checkStillWanted() throws {
        try cancellation.check()
        if abandoned.load(ordering: .relaxed) { throw Abandoned() }
    }
}

/// What has to be known about the source file's audio before the writing starts.
private struct AudioPlan: @unchecked Sendable {
    // The asset and the track are immutable, and only read on the audio thread.
    let asset: AVAsset
    let track: AVAssetTrack
    let timeRange: CMTimeRange
    let channels: Int
    let sampleRate: Double
    let bitRate: Int

    /// Nil when the file has no audio.
    init?(of asset: AVAsset, within timeRange: CMTimeRange) async throws {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return nil }
        let (formats, sourceBitRate) = try await track.load(.formatDescriptions, .estimatedDataRate)
        let description = formats.first?.audioStreamBasicDescription
        self.asset = asset
        self.track = track
        self.timeRange = timeRange
        channels = min(2, max(1, Int(description?.mChannelsPerFrame ?? 2)))
        sampleRate = description.map(\.mSampleRate).flatMap { [44100, 48000].contains($0) ? $0 : nil } ?? 48000
        bitRate = copyAudioBitRate(channels: channels, source: Double(sourceBitRate))
    }
}

/// The source file's first audio track, decoded over the video's time range
/// and encoded as AAC. Reading it through the asset plays out its edit list,
/// and reading only the video's range is the first half of trimming it.
private final class AudioCopy: @unchecked Sendable {
    // Made on the video's thread and then used on the audio's only.
    let reader: AVAssetReader
    private let output: AVAssetReaderAudioMixOutput
    private let input: AVAssetWriterInput
    private let start: CMTime

    init(_ plan: AudioPlan, into job: WritingJob) throws {
        reader = try AVAssetReader(asset: plan.asset)
        reader.timeRange = plan.timeRange
        output = AVAssetReaderAudioMixOutput(audioTracks: [plan.track], audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: plan.sampleRate,
            AVNumberOfChannelsKey: plan.channels,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)

        // An encoder that will not take the rate raises instead of failing, so
        // the rate is asked for only when the writer says it can apply it.
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: plan.sampleRate,
            AVNumberOfChannelsKey: plan.channels,
        ]
        var withRate = settings
        withRate[AVEncoderBitRateKey] = plan.bitRate
        let applicable = job.writer.canApply(outputSettings: withRate, forMediaType: .audio)
        input = AVAssetWriterInput(mediaType: .audio, outputSettings: applicable ? withRate : settings)
        start = plan.timeRange.start
        try job.add(input)
    }

    func run(in job: WritingJob) throws {
        while let buffer = output.copyNextSampleBuffer() {
            guard buffer.numSamples > 0 else { continue }
            // The video starts at zero in the new file, so the audio moves with it.
            let timing = CMSampleTimingInfo(
                duration: buffer.duration, presentationTimeStamp: buffer.presentationTimeStamp - start, decodeTimeStamp: .invalid
            )
            try job.append(try CMSampleBuffer(copying: buffer, withNewTiming: [timing]), to: input)
        }
        guard reader.status == .completed else { throw MediaError.readFailed(describe(reader.error)) }
        input.markAsFinished()
    }
}

extension Result {
    fileprivate var failure: Failure? {
        if case .failure(let failure) = self { failure } else { nil }
    }
}

extension FrameRate {
    var time: CMTime { CMTime(value: duration, timescale: timescale) }
}

extension CGSize {
    /// Scaled down to fit, never up, with even sides as encoders like them.
    fileprivate func fitted(toLongerSide limit: Int?) -> (width: Int, height: Int) {
        let longer = max(width, height)
        let scale = limit.map { min(1, CGFloat($0) / longer) } ?? 1
        func even(_ side: CGFloat) -> Int { max(2, Int((side * scale / 2).rounded()) * 2) }
        return scale < 1 ? (even(width), even(height)) : (Int(width), Int(height))
    }
}
