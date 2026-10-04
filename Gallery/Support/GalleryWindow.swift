import DesignSystem
import SwiftUI

struct GalleryWindow: View {
    @State private var settings = GallerySettings()
    /// `-page <title>` on the command line opens that page, for review screenshots.
    @State private var selection: GalleryPage.ID? = UserDefaults.standard.string(forKey: "page") ?? GalleryPage.all.first?.id

    var body: some View {
        NavigationSplitView {
            List(GalleryPage.all, selection: $selection) { page in
                Label(page.title, systemImage: page.systemImage)
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 220)
        } detail: {
            if let page = GalleryPage.all.first(where: { $0.id == selection }) {
                ScrollView {
                    page.content()
                        .padding(Spacing.extraLarge)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background { Backdrop(isBusy: settings.busyBackdrop) }
                .environment(\.accessibilityOverrides, settings.overrides)
                .navigationTitle(page.title)
                .id(page.id)
            }
        }
        .toolbar { switches }
        .preferredColorScheme(settings.appearance.colorScheme)
    }

    @ToolbarContentBuilder private var switches: some ToolbarContent {
        ToolbarItemGroup {
            Toggle("0.1x", systemImage: "tortoise", isOn: $settings.slowMotion)
                .help("Slow motion: run every animation at a tenth of its speed")
            Toggle("Reduce Motion", systemImage: "figure.walk.motion", isOn: $settings.reduceMotion)
                .help("Reduce Motion")
            Toggle("Reduce Transparency", systemImage: "square.on.square.intersection.dashed", isOn: $settings.reduceTransparency)
                .help("Reduce Transparency")
            Toggle("Increase Contrast", systemImage: "circle.lefthalf.filled", isOn: $settings.increaseContrast)
                .help("Increase Contrast")
            Toggle("Busy Backdrop", systemImage: "photo", isOn: $settings.busyBackdrop)
                .help("Busy backdrop: put a picture behind the glass")
        }
        ToolbarItem {
            Picker("Appearance", selection: $settings.appearance) {
                ForEach(GallerySettings.Appearance.allCases) { appearance in
                    Text(appearance.rawValue).tag(appearance)
                }
            }
            .help("Appearance")
        }
    }
}

/// Behind every page: the window background, or a busy picture to judge glass against.
private struct Backdrop: View {
    let isBusy: Bool

    var body: some View {
        if isBusy {
            SamplePicture(seed: 7)
                .ignoresSafeArea()
        } else {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()
        }
    }
}
