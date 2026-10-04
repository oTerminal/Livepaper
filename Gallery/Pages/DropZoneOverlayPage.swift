import DesignSystem
import SwiftUI

struct DropZoneOverlayPage: View {
    @State private var isTargeted = false
    private let message = "Videos and Live Photos are added to your library."

    var body: some View {
        StateSection(
            title: "Simulated drag",
            note: "The plate scales in from 0.96 and leaves quicker than it came; the scrim and border only fade."
        ) {
            Toggle("Simulate drag", isOn: $isTargeted)
                .toggleStyle(.switch)
            FakeWindow(seed: 31)
                .dropZoneOverlay(isTargeted: isTargeted, title: "Drop to Import", message: message)
                .clipShape(FakeWindow.shape)
        }

        StateSection(title: "Targeted") {
            FakeWindow(seed: 32)
                .dropZoneOverlay(isTargeted: true, title: "Drop to Import", message: message)
                .clipShape(FakeWindow.shape)
        }

        StateSection(title: "Targeted, no message") {
            FakeWindow(seed: 33)
                .dropZoneOverlay(isTargeted: true, title: "Drop to Import")
                .clipShape(FakeWindow.shape)
        }

        StateSection(title: "Idle", note: "Nothing is drawn, and clicks pass through.") {
            FakeWindow(seed: 34)
                .dropZoneOverlay(isTargeted: false, title: "Drop to Import")
                .clipShape(FakeWindow.shape)
        }
    }
}

/// Stands in for the app's window.
private struct FakeWindow: View {
    static let shape = RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)

    let seed: Int

    var body: some View {
        SamplePicture(seed: seed)
            .frame(width: 560, height: 350)
    }
}
