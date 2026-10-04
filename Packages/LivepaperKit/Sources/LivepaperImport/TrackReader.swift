import AVFoundation
import CoreMedia
import Foundation

/// What can go wrong reading or writing a movie file with AVFoundation.
public enum MediaError: Error, Equatable, Sendable {
    case noVideoTrack
    case readFailed(String)
    case writeFailed(String)
}

/// Reads a file's video track exactly as the engine will: `AVAssetReaderTrackOutput`
/// with no output settings, the compressed samples as they are in the file.
///
/// The reader brackets the frames with marker buffers that carry no media (an
/// edit boundary first; drain, notification and empty-media markers last, the
/// last of them stamped with the track's duration). Frames are the buffers
/// with at least one sample.
@concurrent
public func readVideoTrack(of url: URL) async throws -> TrackReading {
    let asset = AVURLAsset(url: url)
    let track = try? await asset.loadTracks(withMediaType: .video).first
    // A cancel makes the load fail too, and must not be taken for a file with no video.
    try Task.checkCancellation()
    guard let track else { throw MediaError.noVideoTrack }
    return try await readVideoTrack(track, of: asset)
}

func readVideoTrack(_ track: AVAssetTrack, of asset: AVAsset) async throws -> TrackReading {
    let (timescale, timeRange, segments) = try await track.load(.naturalTimeScale, .timeRange, .segments)

    let media = Unchecked((asset: asset, track: track))
    let frames = try await onOwnThread { cancellation in
        let reader = try AVAssetReader(asset: media.value.asset)
        let output = AVAssetReaderTrackOutput(track: media.value.track, outputSettings: nil)
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw MediaError.readFailed(describe(reader.error)) }

        var frames: [TrackReading.Frame] = []
        while let buffer = output.copyNextSampleBuffer() {
            if cancellation.isCancelled {
                reader.cancelReading()
                throw CancellationError()
            }
            frames += try buffer.frames(in: timescale)
        }
        guard reader.status == .completed else { throw MediaError.readFailed(describe(reader.error)) }
        return frames
    }

    return TrackReading(
        timescale: timescale,
        frames: frames,
        trackDuration: timeRange.duration.ticks(in: timescale),
        hasEditList: !segments.playMediaAsItIs(frames: frames, timescale: timescale)
    )
}

/// The loop-seam validator: reads the file as the engine will and reports what it finds.
@concurrent
public func validateLoopSeam(of url: URL) async throws -> LoopSeamReport {
    judgeLoopSeam(try await readVideoTrack(of: url))
}

func describe(_ error: (any Error)?) -> String {
    guard let error = error as NSError? else { return "unknown error" }
    return "\(error.domain) \(error.code): \(error.localizedDescription)"
}

extension CMTime {
    func ticks(in timescale: Int32) -> Int64 {
        convertScale(timescale, method: .roundHalfAwayFromZero).value
    }
}

extension CMSampleBuffer {
    /// False for the marker buffers the reader brackets the frames with, which carry no media.
    var carriesMedia: Bool { numSamples > 0 && dataBuffer != nil }

    /// The frames in this buffer: none for a marker.
    fileprivate func frames(in timescale: Int32) throws -> [TrackReading.Frame] {
        guard carriesMedia else { return [] }
        let timings = try sampleTimingInfos()
        let attachments = CMSampleBufferGetSampleAttachmentsArray(self, createIfNecessary: false) as? [[CFString: Any]] ?? []
        return timings.enumerated().map { index, timing in
            let sample = index < attachments.count ? attachments[index] : nil
            let notSync = sample?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
            let partialSync = sample?[kCMSampleAttachmentKey_PartialSync] as? Bool ?? false
            let duration = timing.duration.isNumeric ? timing.duration : self.duration
            return TrackReading.Frame(
                pts: timing.presentationTimeStamp.ticks(in: timescale),
                duration: duration.isNumeric ? duration.ticks(in: timescale) : 0,
                isSync: !notSync && !partialSync
            )
        }
    }
}

extension [AVAssetTrackSegment] {
    /// Whether these edits play the track's media from zero, unscaled and to
    /// its end. Writers put such an edit in every file, and it changes nothing.
    fileprivate func playMediaAsItIs(frames: [TrackReading.Frame], timescale: Int32) -> Bool {
        guard count == 1, let mapping = first?.timeMapping, first?.isEmpty == false else { return isEmpty }
        guard mapping.source.start == .zero, mapping.target.start == .zero, mapping.source.duration == mapping.target.duration else {
            return false
        }
        // An edit that stops short of the frames cuts the end off. Movie
        // timescales are coarse, so anything under a frame is rounding.
        guard let end = frames.map({ $0.pts + $0.duration }).max(), let frame = frames.map(\.duration).max() else { return true }
        return end - mapping.source.duration.ticks(in: timescale) < frame
    }
}
