import Foundation

public enum TransferFunction: String, Equatable, Sendable {
    case sdr
    case hlg
    case pq

    public var isHDR: Bool { self != .sdr }
}

public enum FrameTiming: Equatable, Sendable {
    /// Every step between frames is the same, within a tick of rounding.
    case constant(FrameRate)
    case variable
}

/// How the track says its picture is to be turned before it is shown.
public enum Orientation: Equatable, Sendable {
    case upright
    /// A quarter turn, a half turn or three quarters: 90, 180 or 270.
    case turned(degrees: Int)
    /// A flip, a skew, or anything else that is no turn.
    case transformed
}

/// What the probe found out about a source file's video track.
public struct VideoProbe: Equatable, Sendable {
    /// The four-character code, such as `avc1`, `hvc1` or `apch`.
    public var codec: String
    /// Whether AVFoundation can decode it on this Mac.
    public var isDecodable: Bool
    /// In pixels, as encoded, before the rotation.
    public var width: Int
    public var height: Int
    public var orientation: Orientation
    public var nominalFrameRate: Double
    /// The shortest frame, in seconds. What a variable rate is made constant at.
    public var minFrameDuration: Double
    public var timing: FrameTiming
    public var frameCount: Int
    /// Of the track, in seconds.
    public var duration: Double
    /// The track's samples over its duration, in bits per second. Zero when AVFoundation does not know it.
    public var bitRate: Double
    /// Whether the track's edits do anything but play its media from zero, as it is.
    public var hasEditList: Bool
    /// B-frames: decode order is not presentation order.
    public var hasFrameReordering: Bool
    /// The first frame decoded is a full sync sample and the first frame shown.
    public var startsOnSyncFrame: Bool
    public var transferFunction: TransferFunction

    public init(
        codec: String, isDecodable: Bool, width: Int, height: Int, orientation: Orientation, nominalFrameRate: Double,
        minFrameDuration: Double, timing: FrameTiming, frameCount: Int, duration: Double, bitRate: Double = 0, hasEditList: Bool,
        hasFrameReordering: Bool, startsOnSyncFrame: Bool, transferFunction: TransferFunction
    ) {
        self.codec = codec
        self.isDecodable = isDecodable
        self.width = width
        self.height = height
        self.orientation = orientation
        self.nominalFrameRate = nominalFrameRate
        self.minFrameDuration = minFrameDuration
        self.timing = timing
        self.frameCount = frameCount
        self.duration = duration
        self.bitRate = bitRate
        self.hasEditList = hasEditList
        self.hasFrameReordering = hasFrameReordering
        self.startsOnSyncFrame = startsOnSyncFrame
        self.transferFunction = transferFunction
    }
}

extension VideoProbe {
    /// The codecs the library keeps as they are, by four-character code, with the names the file details show.
    public static let keptCodecs = ["avc1": "h264", "hvc1": "hevc"]
}

public struct AudioProbe: Equatable, Sendable {
    public var codec: String
    /// Of the track, in seconds.
    public var duration: Double

    public init(codec: String, duration: Double) {
        self.codec = codec
        self.duration = duration
    }
}

/// Everything the planner needs to know about a source file.
public struct ProbeResult: Equatable, Sendable {
    /// Nil when the first bytes are of no kind Livepaper reads.
    public var container: Container?
    /// Whether AVFoundation opened it. The tracks below are only known when it did.
    public var isReadable: Bool
    public var isProtected: Bool
    public var video: VideoProbe?
    public var audio: AudioProbe?

    public init(container: Container?, isReadable: Bool, isProtected: Bool = false, video: VideoProbe? = nil, audio: AudioProbe? = nil) {
        self.container = container
        self.isReadable = isReadable
        self.isProtected = isProtected
        self.video = video
        self.audio = audio
    }
}
