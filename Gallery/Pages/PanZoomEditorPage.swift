import DesignSystem
import SwiftUI

struct PanZoomEditorPage: View {
    @State private var zoom: CGFloat = 1.6
    @State private var pan = CGSize.zero
    @State private var restingZoom: CGFloat = 1
    @State private var restingPan = CGSize.zero
    private let picture = SamplePicture.image(seed: 5)
    private static let twoPlaces = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(2))

    var body: some View {
        StateSection(
            title: "Editing",
            note: """
            Drag to move: the picture follows the pointer, and resists once its edge reaches the frame. Let go while moving and \
            it carries on with a bounce; let go at rest past the edge and it returns without one. Pinch or use the slider to \
            zoom. Arrow keys move, + and - zoom, without animation.
            """
        ) {
            PanZoomEditor(image: picture, imageSize: SamplePicture.size, frameAspectRatio: 16 / 10, zoom: $zoom, pan: $pan)
                .frame(width: 480)
            let (across, down) = (Double(pan.width), Double(pan.height))
            Text("zoom \(Double(zoom), format: Self.twoPlaces)  pan \(across, format: Self.twoPlaces), \(down, format: Self.twoPlaces)")
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }

        StateSection(title: "At rest", note: "Zoom 1, nothing to reset. An ultrawide frame, so there is room to move up and down.") {
            PanZoomEditor(image: picture, imageSize: SamplePicture.size, frameAspectRatio: 21 / 9, zoom: $restingZoom, pan: $restingPan)
                .frame(width: 480)
        }

        StateSection(title: "Portrait frame", note: "A display turned on its side.") {
            PanZoomEditor(
                image: picture,
                imageSize: SamplePicture.size,
                frameAspectRatio: 10 / 16,
                zoom: .constant(1),
                pan: .constant(CGSize(width: 0.4, height: 0))
            )
            .frame(width: 200)
        }
    }
}
