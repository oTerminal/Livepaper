import DesignSystem
import LivepaperWorkshop
import SwiftUI

/// The Workshop window: Wallpaper Engine's Workshop on Steam Community, in a
/// web view, with Get in the toolbar for the item whose page is open. What is
/// being got, and then imported, is listed under the page, as the library
/// window lists its imports under the grid. Opened from the library window's
/// toolbar, the File menu and the popover.
struct WorkshopWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(WorkshopModel.self) private var workshop
    @State private var browser = WorkshopBrowser()
    @State private var isConfirmingSignOut = false

    var body: some View {
        VStack(spacing: 0) {
            WorkshopWebView(browser: browser)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if !workshop.downloads.rows.isEmpty || !model.importList.rows.isEmpty {
                Divider()
                WorkshopDownloadList()
                ImportListView()
            }
        }
        .frame(minWidth: Layout.minimum.width, minHeight: Layout.minimum.height)
        .navigationTitle("Wallpaper Engine Workshop")
        .navigationSubtitle(browser.page?.title ?? "")
        .toolbar { toolbar }
        .onAppear { browser.start() }
        .steamSignInSheet(on: .workshop)
        .confirmationDialog("Sign out of Steam?", isPresented: $isConfirmingSignOut) {
            SignOutButtons()
        } message: {
            Text(SteamAccountWords.signOutMessage)
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button("Back", systemImage: "chevron.backward") { browser.goBack() }
                .disabled(!browser.canGoBack)
                .help("Back")
            Button("Forward", systemImage: "chevron.forward") { browser.goForward() }
                .disabled(!browser.canGoForward)
                .help("Forward")
            Button("Workshop Home", systemImage: "house") { browser.goHome() }
                .help("Wallpaper Engine’s Workshop")
        }
        ToolbarItem(placement: .primaryAction) {
            WorkshopGetButton(state: workshop.getState(for: browser.item, page: browser.page)) {
                guard let item = browser.item else { return }
                workshop.get(item, page: browser.page)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            accountMenu
        }
    }

    private var accountMenu: some View {
        Menu {
            if let account = workshop.account {
                Text("Signed in to Steam as \(account)")
                Button("Sign Out of Steam…") { isConfirmingSignOut = true }
                    .disabled(workshop.isSigningOut)
            } else {
                Button("Sign In to Steam…") { workshop.beginSignIn(on: .workshop) }
            }
        } label: {
            Label("Steam Account", systemImage: "person.crop.circle")
        }
        .help(workshop.account.map { "Signed in to Steam as \($0)" } ?? "Not signed in to Steam")
    }
}

private nonisolated enum Layout {
    static let minimum = CGSize(width: 900, height: 600)
}

#Preview("Workshop, signed out") {
    WorkshopWindow()
        .frame(width: 1180, height: 820)
        .environment(AppModel.preview())
        .environment(WorkshopModel.preview())
}
