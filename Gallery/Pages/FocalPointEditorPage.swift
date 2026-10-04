import DesignSystem
import SwiftUI

struct FocalPointEditorPage: View {
    @State private var focalPoint = UnitPoint(x: 0.5, y: 0.5)
    @State private var corner = UnitPoint(x: 1, y: 0)
    private let picture = SamplePicture.image(seed: 3)
    private static let twoPlaces = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))

    var body: some View {
        StateSection(
            title: "Editing",
            note: """
            Drag: the handle follows the pointer exactly. Let go while still moving and it carries on a little, with a bounce; \
            let go at rest and it stays put. Tab to it and use the arrow keys: no animation.
            """
        ) {
            FocalPointEditor(image: picture, imageSize: SamplePicture.size, focalPoint: $focalPoint)
                .frame(width: 480, height: 300)
            Text("x \(Double(focalPoint.x), format: Self.twoPlaces)  y \(Double(focalPoint.y), format: Self.twoPlaces)")
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }

        StateSection(title: "At a corner", note: "The focal point stays on the picture.") {
            FocalPointEditor(image: picture, imageSize: SamplePicture.size, focalPoint: $corner)
                .frame(width: 320, height: 200)
        }

        StateSection(title: "Letterboxed", note: "A wide picture in a tall editor: the handle keeps to the picture, not the editor.") {
            FocalPointEditor(image: picture, imageSize: SamplePicture.size, focalPoint: .constant(UnitPoint(x: 0.3, y: 0.7)))
                .frame(width: 240, height: 300)
                .background(.quaternary, in: .rect(cornerRadius: Radius.tile))
        }
    }
}
