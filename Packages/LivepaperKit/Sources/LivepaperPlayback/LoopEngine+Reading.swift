// Reading the file for the gapless loop: compressed samples straight from `AVAssetReaderTrackOutput`
// with no output settings, one reader per pass. Adapted from Phosphene's VideoRenderer.swift (MIT,
// (c) 2026 kageroumado, https://github.com/kageroumado/phosphene) by way of the spike's LoopEngine.
// See NOTICE at the repository root.

import AVFoundation
import LivepaperCore
import Synchronization

/// The file an engine plays, as far as it has been loaded.
struct LoopMedia {
    let asset: AVURLAsset
    let videoTrack: AVAssetTrack
    /// Loaded only once the volume is up: at 0 the audio track is not opened.
    var audioTrack: AVAssetTrack?
    var audioTrackLoaded = false
    let video: LoopEngine.Video
    let frameDuration: CMTime

    static func load(_ url: URL) async throws -> LoopMedia {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw EngineError.noVideoTrack }
        let (naturalSize, minFrameDuration, nominalFrameRate) = try await track.load(.naturalSize, .minFrameDuration, .nominalFrameRate)
        // The import makes every optimised copy's frames even, so the shortest frame is the frame.
        let frameDuration = if minFrameDuration.isNumeric, minFrameDuration > .zero {
            minFrameDuration
        } else if nominalFrameRate > 0 {
            CMTime(seconds: 1 / Double(nominalFrameRate), preferredTimescale: 90000)
        } else {
            CMTime(value: 1, timescale: 30)
        }
        return LoopMedia(
            asset: asset,
            videoTrack: track,
            video: LoopEngine.Video(
                url: url,
                size: Size(width: abs(naturalSize.width), height: abs(naturalSize.height)),
                frameDuration: frameDuration.seconds
            ),
            frameDuration: frameDuration
        )
    }
}

enum EngineError: Error {
    case noVideoTrack
    case cannotRead(String)
}

/// One pass through the file: a reader of its own, on the video track and, while the volume is
/// up, the audio track too, so that the two stay on the same pass.
final class ReaderPass {
    let reader: AVAssetReader
    let video: AVAssetReaderTrackOutput
    let audio: AVAssetReaderTrackOutput?
    /// Added to this pass's output times. Set when the video enters the pass.
    var offset = CMTime.zero

    init(reading media: LoopMedia, withAudio: Bool) throws {
        reader = try AVAssetReader(asset: media.asset)
        // No output settings: the compressed samples go straight to the layer, which decodes in hardware.
        video = AVAssetReaderTrackOutput(track: media.videoTrack, outputSettings: nil)
        video.alwaysCopiesSampleData = false
        guard reader.canAdd(video) else { throw EngineError.cannotRead("the video track cannot be read") }
        reader.add(video)

        if withAudio, let track = media.audioTrack {
            let audio = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
            audio.alwaysCopiesSampleData = false
            if reader.canAdd(audio) {
                reader.add(audio)
                self.audio = audio
            } else {
                self.audio = nil
            }
        } else {
            audio = nil
        }

        guard reader.startReading() else {
            throw EngineError.cannotRead(reader.error.map { "\($0)" } ?? "the reader did not start")
        }
    }

    func cancel() {
        reader.cancelReading()
    }
}

extension CMSampleBuffer {
    var vended: VendedBuffer {
        VendedBuffer(
            sampleCount: numSamples,
            hasDataBuffer: dataBuffer != nil,
            presentationTime: presentationTimeStamp,
            outputPresentationTime: outputPresentationTimeStamp,
            decodeTime: decodeTimeStamp,
            duration: duration
        )
    }

    /// A copy with every time moved by `shift`, sharing the data. The copy's output times follow
    /// its new presentation times.
    func shifted(by shift: CMTime) -> CMSampleBuffer? {
        guard shift != .zero else { return self }
        guard let timings = try? sampleTimingInfos() else { return nil }
        let moved = timings.map { timing in
            var moved = timing
            if timing.presentationTimeStamp.isNumeric { moved.presentationTimeStamp = timing.presentationTimeStamp + shift }
            if timing.decodeTimeStamp.isNumeric { moved.decodeTimeStamp = timing.decodeTimeStamp + shift }
            return moved
        }
        return try? CMSampleBuffer(copying: self, withNewTiming: moved)
    }

    /// Output time minus media time: what the edit list moves this buffer by.
    var editShift: CMTime {
        let output = outputPresentationTimeStamp
        let media = presentationTimeStamp
        return output.isNumeric && media.isNumeric ? output - media : .zero
    }

    /// Shown as soon as it is decoded, whatever the clock says: the first frame of a start.
    func displayImmediately() {
        setOnFirstSample(kCMSampleAttachmentKey_DisplayImmediately)
    }

    /// Decoded and never shown: the frame that gives the hardware decoder back.
    func doNotDisplay() {
        setOnFirstSample(kCMSampleAttachmentKey_DoNotDisplay)
    }

    private func setOnFirstSample(_ key: CFString) {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(self, createIfNecessary: true),
              CFArrayGetCount(attachments) > 0 else { return }
        let first = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
        CFDictionarySetValue(
            first,
            Unmanaged.passUnretained(key).toOpaque(),
            Unmanaged.passUnretained(kCFBooleanTrue).toOpaque()
        )
    }

    func dropDecoderReset() {
        CMRemoveAttachment(self, key: kCMSampleBufferAttachmentKey_ResetDecoderBeforeDecoding)
    }
}

/// Resumes a continuation the first time anyone asks, and ignores the rest: a callback that
/// may never come, raced against a deadline.
final class ResumeOnce: Sendable {
    private let continuation: Mutex<CheckedContinuation<Void, Never>?>

    init(_ continuation: CheckedContinuation<Void, Never>) {
        self.continuation = Mutex(continuation)
    }

    func resume() {
        continuation.withLock { $0.take() }?.resume()
    }
}

/// The engine's own numbers for the metrics line, carried across the restarts of one video.
struct EngineTally {
    var loops = 0
    var markersSkipped = 0
    var largestSeamStep: Double?
    var largestInLoopStep: Double?
    var smallestSeamLead: Double?
    var flushes = 0
    var failures = 0
    var nextReaderMisses = 0

    /// Adds in the books of a start that is over.
    mutating func fold(_ ledger: PassLedger) {
        loops += ledger.loops
        markersSkipped += ledger.markersSkipped
        largestSeamStep = larger(largestSeamStep, ledger.largestSeamStep)
        largestInLoopStep = larger(largestInLoopStep, ledger.largestInLoopStep)
    }

    private func larger(_ first: Double?, _ second: Double?) -> Double? {
        switch (first, second) {
        case (let first?, let second?): max(first, second)
        case (let value?, nil), (nil, let value?): value
        case (nil, nil): nil
        }
    }
}
