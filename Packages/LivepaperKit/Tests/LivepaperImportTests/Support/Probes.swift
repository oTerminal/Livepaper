import Foundation
import LivepaperImport

extension VideoProbe {
    /// What the library keeps as it is: H.264, SDR, 30 fps constant, clean timing, upright.
    static func clean(_ change: (inout VideoProbe) -> Void = { _ in }) -> VideoProbe {
        var probe = VideoProbe(
            codec: "avc1", isDecodable: true, width: 1920, height: 1080, orientation: .upright, nominalFrameRate: 30,
            minFrameDuration: 1.0 / 30, timing: .constant(FrameRate(duration: 512, timescale: 15360)), frameCount: 150, duration: 5,
            hasEditList: false, hasFrameReordering: false, startsOnSyncFrame: true, transferFunction: .sdr
        )
        change(&probe)
        return probe
    }
}

extension ProbeResult {
    static func isoMedia(_ change: (inout VideoProbe) -> Void = { _ in }) -> ProbeResult {
        ProbeResult(container: .isoMedia, isReadable: true, video: .clean(change))
    }
}

extension WallpaperEngineProject {
    /// A project the tests know to be a good one.
    static func known(
        kind: WallpaperEngineItemKind = .video, title: String? = nil, file: String, preview: String? = nil
    ) -> WallpaperEngineProject {
        guard let project = try? WallpaperEngineProject(kind: kind, title: title, file: file, preview: preview) else {
            preconditionFailure("not a contained path: \(file)")
        }
        return project
    }
}
