import DesignSystem
import SwiftUI

struct FitModePickerPage: View {
    @State private var fit = "Fill"
    @State private var pair = "Fit"
    @State private var disabled = "Fit"

    private let three = [
        FitModeOption(value: "Fill", title: "Fill", systemImage: "arrow.up.left.and.arrow.down.right"),
        FitModeOption(value: "Fit", title: "Fit", systemImage: "arrow.down.right.and.arrow.up.left"),
        FitModeOption(value: "Stretch", title: "Stretch", systemImage: "arrow.left.and.right"),
    ]

    var body: some View {
        StateSection(
            title: "Over a preview",
            note: """
            Click a segment and the pill slides (offset, Motion.Spring.ui). Tab to the control and use the left and right \
            arrow keys: the pill jumps. With Reduce Motion the pill crossfades instead of sliding.
            """
        ) {
            preview(seed: 3) {
                FitModePicker("Fit mode", selection: $fit, options: three)
            }
        }

        StateSection(title: "Two options") {
            preview(seed: 5) {
                FitModePicker("Fit mode", selection: $pair, options: Array(three.prefix(2)))
            }
        }

        StateSection(title: "Disabled") {
            preview(seed: 6) {
                FitModePicker("Fit mode", selection: $disabled, options: three)
                    .disabled(true)
            }
        }
    }

    private func preview(seed: Int, @ViewBuilder control: () -> some View) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
        return SamplePicture(seed: seed)
            .frame(width: 480, height: 300)
            .clipShape(shape)
            .imageOutline(shape)
            .overlay(alignment: .bottom) {
                control()
                    .padding(Spacing.large)
            }
    }
}
