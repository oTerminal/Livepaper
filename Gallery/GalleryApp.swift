import DesignSystem
import SwiftUI

/// Shows every design-system component in isolation, in every state, for review.
@main
struct GalleryApp: App {
    var body: some Scene {
        WindowGroup("Livepaper Gallery") {
            GalleryWindow()
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}
