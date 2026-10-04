import DesignSystem
import LivepaperCore
import SwiftUI

/// The popover's last rows: Mute and Pause All, which act on every display, the
/// ways into the Workshop, the library and Settings, and the status line under them.
struct PopoverFooter: View {
    @Environment(AppModel.self) private var model
    @Environment(AppWindows.self) private var windows

    var body: some View {
        // Nothing can be saved while the library could not be read, and a Pause
        // All could not be resumed: both wait until it can.
        let canChange = model.libraryProblem == nil
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                mute
                    .disabled(!canChange)
                pauseAll
                    .disabled(!canChange)
                // Pause All and Resume All differ in width; the buttons after the gap stay put.
                Spacer(minLength: Spacing.small)
                SymbolButton("Wallpaper Engine Workshop", systemImage: "globe") { windows.openWorkshop() }
                SymbolButton("Open Library", systemImage: "square.grid.2x2") { windows.openLibrary() }
                SymbolButton("Settings", systemImage: "gearshape") { windows.openSettings() }
            }
            HStack(spacing: Spacing.small) {
                StatusLine(status: model.statusLine.statusLineStatus) { model.restartWallpaperService() }
                    // As wide as its words, so that the pane's button follows them as Restart does.
                    .fixedSize(horizontal: model.offersWallpaperPane, vertical: false)
                if model.offersWallpaperPane {
                    // Another wallpaper was picked by hand: the user chooses Livepaper
                    // again in System Settings, and nothing in the store is touched.
                    CompactTextButton(title: Text("Open System Settings…")) { model.openWallpaperPane() }
                    Spacer(minLength: 0)
                }
            }
            // Its words start under Mute's speaker, not 1 to 2 pt left of it: LabelToggle
            // centres the speaker in its 20 pt slot, so the glyph sits 3 to 4 pt inside
            // the slot's edge. The hairline is the optical step; the waves' speaker then
            // stands 1 pt out, as a symbol beside words does, and the slashed one lines up.
            .padding(.leading, Spacing.small + Spacing.hairline)
            .padding(.trailing, Spacing.small)
        }
    }

    /// Its words stay "Mute"; the slashed speaker and the toggle's fill say it is on.
    private var mute: some View {
        LabelToggle(
            "Mute",
            systemImage: model.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
            isOn: Binding { model.isMuted } set: { model.setMuted($0) }
        )
        .help(model.isMuted ? "Every display is muted" : "Mute every display")
    }

    private var pauseAll: some View {
        LabelButton(
            model.isPausedAll ? "Resume All" : "Pause All",
            systemImage: model.isPausedAll ? "play.fill" : "pause.fill"
        ) {
            model.togglePauseAll()
        }
        .help(model.isPausedAll ? "Play every display again" : "Pause every display")
    }
}
