import Foundation

/// Why a source file cannot become a wallpaper, for the UI to put into words.
public enum RejectReason: Equatable, Sendable {
    /// Not a kind of file Livepaper reads.
    case unrecognised
    case noVideo
    case noFrames
    /// Copy-protected: it cannot be read, let alone converted.
    case protected
}

public enum ImportPlan: Equatable, Sendable {
    /// Already what the library keeps. The samples are copied as they are into a file with clean timing.
    case remux
    /// Decoded and encoded again with AVFoundation.
    case transcode
    /// Converted by the ffmpeg helper first, then planned again.
    case ffmpeg
    case reject(RejectReason)
}

/// Picks the cheapest conversion that ends in an optimised copy that loops without a gap.
public func planImport(_ probe: ProbeResult) -> ImportPlan {
    guard let container = probe.container else { return .reject(.unrecognised) }
    guard container == .isoMedia, probe.isReadable else { return .ffmpeg }
    guard !probe.isProtected else { return .reject(.protected) }
    guard let video = probe.video else { return .reject(.noVideo) }
    guard video.frameCount > 0 else { return .reject(.noFrames) }
    guard video.isDecodable else { return .ffmpeg }

    // Anything the remux cannot put right without touching the samples.
    let keptAsItIs = VideoProbe.keptCodecs.keys.contains(video.codec)
        && !video.transferFunction.isHDR
        && video.timing != .variable
        && !video.hasEditList
        && !video.hasFrameReordering
        && video.startsOnSyncFrame
        && video.orientation == .upright
    return keptAsItIs ? .remux : .transcode
}
