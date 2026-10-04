import AVFoundation
import CoreMedia
import Foundation

/// Finds out what the planner needs to know about a source file. Nothing is written.
@concurrent
public func probeSource(at url: URL) async throws -> ProbeResult {
    // By its bytes, never by its name: a WebM called .mp4 still goes to ffmpeg.
    guard let container = try Container.sniff(contentsOf: url) else { return ProbeResult(container: nil, isReadable: false) }
    guard container == .isoMedia else { return ProbeResult(container: container, isReadable: false) }

    let asset = AVURLAsset(url: url)
    let tracks = try? await asset.load(.tracks)
    // A cancel makes the load fail too, and must not be taken for a file AVFoundation cannot open.
    try Task.checkCancellation()
    guard let tracks, !tracks.isEmpty else { return ProbeResult(container: container, isReadable: false) }
    var result = ProbeResult(container: container, isReadable: true)
    result.isProtected = (try? await asset.load(.hasProtectedContent)) ?? false

    if let track = tracks.first(where: { $0.mediaType == .video }), !result.isProtected {
        result.video = try await probeVideo(track, of: asset)
    }
    if let track = tracks.first(where: { $0.mediaType == .audio }) {
        let (timeRange, formats) = try await track.load(.timeRange, .formatDescriptions)
        result.audio = AudioProbe(codec: formats.first?.mediaSubType.description.fourCharacters ?? "", duration: timeRange.duration.seconds)
    }
    return result
}

private func probeVideo(_ track: AVAssetTrack, of asset: AVAsset) async throws -> VideoProbe {
    let (formats, isDecodable, transform, nominalFrameRate, minFrameDuration, timeRange, bitRate) = try await track.load(
        .formatDescriptions, .isDecodable, .preferredTransform, .nominalFrameRate, .minFrameDuration, .timeRange, .estimatedDataRate
    )
    let format = formats.first
    let dimensions = format.map { CMVideoFormatDescriptionGetDimensions($0) } ?? CMVideoDimensions(width: 0, height: 0)
    // An undecodable track cannot be read as the engine reads it, and its timing does not matter: it goes to ffmpeg.
    let reading = isDecodable ? try await readVideoTrack(track, of: asset) : nil

    return VideoProbe(
        codec: format?.mediaSubType.description.fourCharacters ?? "",
        isDecodable: isDecodable,
        width: Int(dimensions.width),
        height: Int(dimensions.height),
        orientation: transform.orientation,
        nominalFrameRate: Double(nominalFrameRate),
        minFrameDuration: minFrameDuration.isNumeric ? minFrameDuration.seconds : 0,
        timing: reading?.timing ?? .variable,
        frameCount: reading?.frames.count ?? 0,
        duration: timeRange.duration.seconds,
        bitRate: Double(bitRate),
        hasEditList: reading?.hasEditList ?? false,
        hasFrameReordering: reading?.hasFrameReordering ?? false,
        startsOnSyncFrame: reading?.startsOnSyncFrame ?? false,
        transferFunction: format?.transferFunction ?? .sdr
    )
}

extension TrackReading {
    /// Constant when every step between frames, in presentation order, is the first frame's duration within a tick.
    var timing: FrameTiming {
        let shown = frames.sorted { $0.pts < $1.pts }
        guard let duration = shown.first?.duration, duration > 0 else { return .variable }
        let isConstant = zip(shown, shown.dropFirst()).allSatisfy { abs($1.pts - $0.pts - duration) <= 1 }
        return isConstant ? .constant(FrameRate(duration: duration, timescale: timescale)) : .variable
    }

    var hasFrameReordering: Bool {
        zip(frames, frames.dropFirst()).contains { $1.pts < $0.pts }
    }

    var startsOnSyncFrame: Bool {
        guard let first = frames.first else { return false }
        return first.isSync && frames.allSatisfy { $0.pts >= first.pts }
    }
}

extension CMFormatDescription {
    fileprivate var transferFunction: TransferFunction {
        let value = CMFormatDescriptionGetExtension(self, extensionKey: kCMFormatDescriptionExtension_TransferFunction) as? String
        if value == (kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG as String) { return .hlg }
        if value == (kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ as String) { return .pq }
        return .sdr
    }
}

extension CGAffineTransform {
    fileprivate var orientation: Orientation {
        switch (a, b, c, d) {
        case (1, 0, 0, 1): .upright
        case (0, 1, -1, 0): .turned(degrees: 90)
        case (-1, 0, 0, -1): .turned(degrees: 180)
        case (0, -1, 1, 0): .turned(degrees: 270)
        default: .transformed
        }
    }
}

extension String {
    /// `'avc1'` as `avc1`.
    fileprivate var fourCharacters: String {
        trimmingCharacters(in: CharacterSet(charactersIn: "'"))
    }
}
