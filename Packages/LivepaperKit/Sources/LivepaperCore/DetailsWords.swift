import Foundation

// What the inspector's details say about a wallpaper's optimised copy, in
// English only for v1.0. Its size and the day it was imported are the system's
// own formats, so the app formats those.

/// One row of the inspector's details.
public enum WallpaperDetail: Equatable, Sendable {
    case kind
    case resolution
    case length
    case frameRate
    case codec
    case size
    case imported
}

extension Wallpaper {
    /// The rows the inspector shows, in order. A video's are what they always
    /// were. A scene has no length and no codec, and says what it is, since
    /// nothing else on screen does.
    public var detailsShown: [WallpaperDetail] {
        switch kind {
        case .video: [.resolution, .length, .frameRate, .codec, .size, .imported]
        case .scene: [.kind, .resolution, .frameRate, .size, .imported]
        }
    }
}

extension WallpaperKind {
    /// "Video", or "Wallpaper Engine scene".
    public var words: String {
        switch self {
        case .video: "Video"
        case .scene: "Wallpaper Engine scene"
        }
    }
}

extension WallpaperDetails {
    /// "3840 × 2160".
    public var resolutionWords: String {
        "\(width) × \(height)"
    }

    /// "0:24", or "1:02:03" from an hour, to the nearest second; any length at
    /// all is at least a second.
    public var lengthWords: String {
        let seconds = duration > 0 ? max(Int(duration.rounded()), 1) : 0
        let (hours, minutes, rest) = (seconds / 3600, seconds / 60 % 60, seconds % 60)
        return hours > 0 ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }

    /// "30 fps", "29.97 fps": the importer keeps two decimal places, and a zero
    /// at the end says nothing.
    public var frameRateWords: String {
        let hundredths = Int((frameRate * 100).rounded())
        var number = String(format: "%d.%02d", hundredths / 100, hundredths % 100)
        while number.hasSuffix("0") { number.removeLast() }
        if number.hasSuffix(".") { number.removeLast() }
        return "\(number) fps"
    }

    /// The codec as people know it: "HEVC", "H.264", "ProRes".
    public var codecWords: String {
        switch codec.lowercased() {
        case "hevc", "hvc1", "hev1": "HEVC"
        case "h264", "avc1": "H.264"
        case "prores", "apcn", "apch", "apcs", "apco", "ap4h", "ap4x": "ProRes"
        default: codec.uppercased()
        }
    }
}
