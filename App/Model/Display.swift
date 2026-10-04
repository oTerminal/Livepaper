import CoreGraphics
import DesignSystem
import LivepaperCore

/// A connected display, named as macOS names it.
struct Display: Identifiable, Equatable {
    let identity: DisplayIdentity
    /// "Built-in Retina Display", "Studio Display".
    let name: String
    /// The current mode's size in pixels.
    let pixelSize: Size

    var id: DisplayIdentity { identity }

    /// Width over height: the frame the pan and zoom editor shows.
    var aspectRatio: CGFloat {
        pixelSize.width > 0 && pixelSize.height > 0 ? pixelSize.width / pixelSize.height : 16.0 / 10
    }

    /// How `SetOnDisplayButton` names it: the design system takes string identifiers.
    var targetID: SetOnDisplayTarget.ID { identity.description }
}
