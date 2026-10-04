import SwiftUI

/// What one step of an `OnboardingCard` says and offers. The card takes every
/// step's, so that it can be as tall as the tallest before any is shown.
public struct OnboardingCardStep: Hashable, Sendable {
    public var title: String
    public var message: String
    public var primaryTitle: String
    public var secondaryTitle: String?
    /// Whether the card's accessory belongs to this step.
    public var showsAccessory: Bool

    public init(title: String, message: String, primaryTitle: String, secondaryTitle: String? = nil, showsAccessory: Bool = false) {
        self.title = title
        self.message = message
        self.primaryTitle = primaryTitle
        self.secondaryTitle = secondaryTitle
        self.showsAccessory = showsAccessory
    }
}

/// When a new primary button of an `OnboardingCard` takes the focus.
public nonisolated enum OnboardingCardFocus {
    /// A new title within a step takes it at once, and so does a step changed by
    /// Return, where nothing fades. A step that crossfades gives it when the
    /// crossfade is over (`Duration.menu`, at the Gallery's motion speed), so no
    /// ring is drawn over the step still fading out.
    public static func delay(stepChanged: Bool, crossfades: Bool, motionSpeed: Double) -> TimeInterval {
        stepChanged && crossfades ? Motion.Duration.menu / motionSpeed : 0
    }
}

/// What the last step change's transaction said, read when the focus moves. A
/// reference, since a transaction is read while the view updates, where state
/// may not change.
final class OnboardingCardStepChange {
    var crossfades = false
}

/// Lays out an `OnboardingCard`'s showing page and its unseen sizing pages on
/// top of one another, as tall as the tallest, and gives every page that height:
/// the showing page's dots and buttons sit at its bottom, where the tallest step
/// has them.
struct OnboardingCardPageLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(ProposedViewSize(width: proposal.width, height: nil)) }
        return CGSize(
            width: proposal.width ?? sizes.map(\.width).max() ?? 0,
            height: sizes.map(\.height).max() ?? 0
        )
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
        }
    }
}
