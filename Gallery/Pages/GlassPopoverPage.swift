import DesignSystem
import SwiftUI

struct GlassPopoverPage: View {
    @State private var isBelowPresented = false
    @State private var isAbovePresented = false
    @State private var isKeyPresented = false

    var body: some View {
        StateSection(
            title: "Opened by a click",
            note: "Grows from the edge that touches its trigger: 0.18 s in, 0.7x out. Escape closes it without animation."
        ) {
            HStack(spacing: Spacing.section) {
                Button("Below, leading") { isBelowPresented.toggle() }
                    .glassPopover(isPresented: $isBelowPresented, alignment: .leading) { sample }
                Button("Above, centred") { isAbovePresented.toggle() }
                    .glassPopover(isPresented: $isAbovePresented, edge: .top) { sample }
            }
            .padding(.top, Spacing.section * 4)
            .padding(.bottom, Spacing.section * 5)
        }
        .zIndex(1)

        StateSection(title: "Opened by a key press", note: "Press the button with Space or Return, or Command-K: no animation.") {
            Button("Toggle (⌘K)") {
                withoutAnimation { isKeyPresented.toggle() }
            }
            .keyboardShortcut("k", modifiers: .command)
            .glassPopover(isPresented: $isKeyPresented, alignment: .leading) { sample }
            .padding(.bottom, Spacing.section * 5)
        }
        .zIndex(1)

        StateSection(title: "Open", note: "The panel on its own. Turn on the busy backdrop and Reduce Transparency.") {
            GlassPopover { sample }
                .fixedSize()
        }
    }

    private var sample: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text("Built-in Display")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("Harbour at Dusk")
                .font(.headline)
            Divider()
            Button("Next Wallpaper") {}
            Button("Pause") {}
        }
        .frame(width: 220, alignment: .leading)
    }
}
