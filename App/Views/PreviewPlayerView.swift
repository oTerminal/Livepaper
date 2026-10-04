import DesignSystem
import LivepaperCore
import LivepaperPlayback
import LivepaperSystem
import os
import SwiftUI

/// A wallpaper playing in a view: the inspector's preview, and a tile's live
/// preview (the hover preview file). One `PreviewPlayer`, laid out by the
/// presentation as a display would be.
///
/// It stops when `url` goes nil. Hidden, or out of its window, the player gives
/// its decoder up by itself and starts again from the first frame when shown, so
/// nothing here has to.
struct PreviewPlayerView: NSViewRepresentable {
    /// The optimised copy or the hover preview; nil shows nothing.
    var url: URL?
    var presentation: Presentation
    /// 0 to 1. At 0 the audio track is not opened.
    var volume: Double = 0
    /// Where there is no picture. The inspector keeps black, which is also Fit's
    /// bars; a tile passes clear, so its poster shows until the first frame.
    var backgroundColor = PreviewPlayer.defaultBackgroundColor

    private static let logger = Logger(subsystem: LivepaperSystem.logSubsystem, category: "preview")

    func makeNSView(context: Context) -> PreviewPlayer {
        let player = PreviewPlayer(logger: Self.logger, presentation: presentation)
        player.volume = volume
        player.backgroundColor = backgroundColor
        return player
    }

    func updateNSView(_ player: PreviewPlayer, context: Context) {
        player.presentation = presentation
        player.volume = volume
        if player.backgroundColor != backgroundColor {
            player.backgroundColor = backgroundColor
        }
        if let url {
            // The URL already playing is a no-op.
            player.play(url)
        } else if player.url != nil {
            player.stop()
        }
    }
}

#Preview("Fill, Fit and nothing") {
    // A fixture of the import tests, found from this file on the machine running the preview.
    let clip = URL(filePath: #filePath)
        .deletingLastPathComponent()
        .appending(path: "../../Packages/LivepaperKit/Tests/LivepaperImportTests/Fixtures/plain-h264.mp4")
        .standardizedFileURL
    HStack(spacing: Spacing.large) {
        PreviewPlayerView(url: clip, presentation: Presentation(fit: .fill))
            .aspectRatio(1, contentMode: .fit)
        PreviewPlayerView(url: clip, presentation: Presentation(fit: .fit))
            .aspectRatio(1, contentMode: .fit)
        PreviewPlayerView(url: nil, presentation: Presentation())
            .aspectRatio(1, contentMode: .fit)
    }
    .frame(width: 720)
    .padding(Spacing.large)
}
