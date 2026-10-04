import SwiftUI

struct GalleryPage: Identifiable {
    let title: String
    let systemImage: String
    let content: () -> AnyView

    var id: String { title }

    init(_ title: String, systemImage: String, @ViewBuilder content: @escaping () -> some View) {
        self.title = title
        self.systemImage = systemImage
        self.content = { AnyView(content()) }
    }

    /// One page per component; later additions sit beside the component they were made next to.
    static let all: [GalleryPage] = [
        GalleryPage("SidebarRow", systemImage: "sidebar.left") { SidebarRowPage() },
        GalleryPage("WallpaperTile", systemImage: "photo.on.rectangle") { WallpaperTilePage() },
        GalleryPage("FavouriteToggle", systemImage: "heart") { FavouriteTogglePage() },
        GalleryPage("FitModePicker", systemImage: "rectangle.split.3x1") { FitModePickerPage() },
        GalleryPage("VolumeSlider", systemImage: "speaker.wave.2") { VolumeSliderPage() },
        GalleryPage("FocalPointEditor", systemImage: "scope") { FocalPointEditorPage() },
        GalleryPage("PanZoomEditor", systemImage: "arrow.up.and.down.and.arrow.left.and.right") { PanZoomEditorPage() },
        GalleryPage("SetOnDisplayButton", systemImage: "display") { SetOnDisplayButtonPage() },
        GalleryPage("DetailsList", systemImage: "list.bullet.rectangle") { DetailsListPage() },
        GalleryPage("GlassPopover", systemImage: "bubble.middle.top") { GlassPopoverPage() },
        GalleryPage("DisplayNowPlayingCard", systemImage: "play.display") { DisplayNowPlayingCardPage() },
        GalleryPage("TransportCluster", systemImage: "playpause") { TransportClusterPage() },
        GalleryPage("LabelButton, LabelToggle and SymbolButton", systemImage: "button.horizontal") { LabelButtonPage() },
        GalleryPage("PlaylistPicker", systemImage: "rectangle.stack") { PlaylistPickerPage() },
        GalleryPage("RecentsStrip", systemImage: "clock.arrow.circlepath") { RecentsStripPage() },
        GalleryPage("DropZoneOverlay", systemImage: "square.and.arrow.down") { DropZoneOverlayPage() },
        GalleryPage("ImportProgressRow", systemImage: "arrow.down.circle") { ImportProgressRowPage() },
        // For the Workshop window.
        GalleryPage("WorkshopGetButton", systemImage: "arrow.down.to.line") { WorkshopGetButtonPage() },
        GalleryPage("SteamSignInForm", systemImage: "person.badge.key") { SteamSignInFormPage() },
        GalleryPage("Toast and UndoToast", systemImage: "rectangle.bottomthird.inset.filled") { ToastPage() },
        GalleryPage("EmptyState", systemImage: "tray") { EmptyStatePage() },
        GalleryPage("OnboardingCard", systemImage: "rectangle.stack.badge.play") { OnboardingCardPage() },
        GalleryPage("HotkeyRecorder", systemImage: "keyboard") { HotkeyRecorderPage() },
        GalleryPage("LoginItemRow", systemImage: "power") { LoginItemRowPage() },
        GalleryPage("PauseRuleToggle", systemImage: "pause.circle") { PauseRuleTogglePage() },
        GalleryPage("StatusLine", systemImage: "text.line.last.and.arrowtriangle.forward") { StatusLinePage() },
    ]
}
