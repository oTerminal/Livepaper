import AppKit
import SwiftUI

/// One step of first-run onboarding: an illustration, a title, a sentence, a
/// page indicator and one or two buttons, on an opaque card in the content layer.
///
/// Its three groups (illustration, text, buttons) enter once, 0.10 s apart, when
/// the card first appears, and never again. To move between steps, change the
/// card's values and keep its identity: the picture crossfades, and so does the
/// rest of the step (words, accessory, dots and buttons) as one page; nothing
/// re-enters. The card tells a click from a key press itself: Return presses the
/// primary button too, and then the step changes with no animation. Give the card
/// a new `.id` only to replay the entrance.
///
/// Given every step (`init(steps:…)`), the card is as tall as its tallest step in
/// all of them, so a step change happens in a still frame: a shorter step's words
/// stay at the top and its dots and buttons at the bottom, where every step has
/// them. Given one step, it is as tall as that step.
///
/// An accessory, when a step needs controls of its own (onboarding's samples to
/// choose from), sits under the words and enters with them. Unlike the
/// illustration, which is a picture and hidden from VoiceOver, it is read and
/// can be pressed. A card alone (`stepCount` 1) shows no page dots.
///
/// Each step opens with keyboard focus on the primary button, the one Return
/// presses, so that Space and Return do the same thing until the user tabs away.
/// A disabled card shows no focus, and gives it back to the primary when enabled.
public struct OnboardingCard<Illustration: View, Accessory: View>: View {
    @Accessibility private var accessibility
    @Environment(\.colorScheme) private var scheme
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.isEnabled) private var isEnabled
    @State private var hasEntered = false
    /// The last primary button the card gave the focus to.
    @State private var focusedOpening: Opening?
    /// The primary button that has the focus, by step and title: the step being
    /// left is still on screen, fading out, when the next one opens, and a new
    /// title within a step is a new button, which the same value would not move to.
    @FocusState private var focusedPrimary: Opening?
    @State private var stepChange = OnboardingCardStepChange()

    private let step: OnboardingCardStep
    /// The steps the card is as tall as, the one showing among them.
    private let sizingSteps: [OnboardingCardStep]
    private let stepIndex: Int
    private let stepCount: Int
    private let onPrimary: () -> Void
    private let onSecondary: (() -> Void)?
    private let illustration: Illustration
    private let accessory: Accessory

    /// A card that knows every step, and is as tall as the tallest of them at
    /// each one. The accessory shows on the steps that say so.
    ///
    /// - Parameters:
    ///   - stepIndex: Zero-based, into `steps`; VoiceOver reads it one-based ("Step 2 of 4").
    ///   - onPrimary: The primary button of the step showing.
    ///   - onSecondary: Its secondary button, when the step has one.
    public init(
        steps: [OnboardingCardStep],
        stepIndex: Int,
        onPrimary: @escaping () -> Void,
        onSecondary: (() -> Void)? = nil,
        @ViewBuilder illustration: () -> Illustration,
        @ViewBuilder accessory: () -> Accessory
    ) {
        let index = steps.indices.contains(stepIndex) ? stepIndex : 0
        self.step = steps.indices.contains(index) ? steps[index] : OnboardingCardStep(title: "", message: "", primaryTitle: "")
        self.sizingSteps = steps
        self.stepIndex = index
        self.stepCount = steps.count
        self.onPrimary = onPrimary
        self.onSecondary = onSecondary
        self.illustration = illustration()
        self.accessory = accessory()
    }

    /// A card that knows only the step it shows, and is as tall as that step.
    ///
    /// - Parameter stepIndex: Zero-based; VoiceOver reads it one-based ("Step 2 of 4").
    public init(
        title: String,
        message: String,
        stepIndex: Int,
        stepCount: Int,
        primaryTitle: String,
        onPrimary: @escaping () -> Void,
        secondaryTitle: String? = nil,
        onSecondary: (() -> Void)? = nil,
        @ViewBuilder illustration: () -> Illustration,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.step = OnboardingCardStep(
            title: title, message: message, primaryTitle: primaryTitle, secondaryTitle: secondaryTitle, showsAccessory: true
        )
        self.sizingSteps = []
        self.stepIndex = stepIndex
        self.stepCount = stepCount
        self.onPrimary = onPrimary
        self.onSecondary = onSecondary
        self.illustration = illustration()
        self.accessory = accessory()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
        VStack(alignment: .leading, spacing: Spacing.large) {
            picture
                .entering(group: 0, hasEntered: hasEntered)
            pages
        }
        .padding(Spacing.small)
        .frame(width: Metrics.width)
        // Nothing is ever drawn outside the card, whatever a caller's step holds.
        .clipShape(shape)
        .background(fill, in: shape)
        .overlay {
            // Only under Increase Contrast, where a shadow alone is too faint an edge.
            if accessibility.increaseContrast {
                shape.strokeBorder(.separator, lineWidth: 2)
            } else if scheme == .dark {
                // Black shadows vanish on a dark window; a faint pure-white ring keeps the edge.
                shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .containerShape(shape)
        .shadow(color: .black.opacity(0.06), radius: Metrics.contactShadowRadius, y: Metrics.contactShadowOffset)
        .shadow(color: .black.opacity(0.14), radius: Metrics.ambientShadowRadius, y: Metrics.ambientShadowOffset)
        .onAppear { hasEntered = true }
        // Left to AppKit, the focus went to the window's first control (onboarding's
        // first sample, or a secondary button laid out before the primary), so the
        // card places it: on each new primary button, once its window is key.
        .onChange(of: activeState, initial: true) { focusNewPrimary() }
        // A new primary button, of a new step or a new title, first lets go of the
        // focus the old one had, then takes it: at once for a new title, and when
        // the crossfade is over for a new step. By Return nothing animates, and the
        // focus moves at once. (A transaction's animation completion was tried first,
        // and never came.)
        .onChange(of: Opening(step: stepIndex, primaryTitle: step.primaryTitle)) { old, new in
            letGoOfFocus()
            let delay = OnboardingCardFocus.delay(
                stepChanged: old.step != new.step, crossfades: stepChange.crossfades, motionSpeed: accessibility.motionSpeed
            )
            Task {
                if delay > 0 { try? await Task.sleep(for: .seconds(delay)) }
                focusNewPrimary()
            }
        }
        // A disabled control shows no focus: a busy card's primary kept its ring.
        // Enabled again, it goes back to the button that had it; a new step's, enabled
        // in the same change, is placed when its crossfade is over.
        .onChange(of: isEnabled) {
            if !isEnabled {
                letGoOfFocus()
            } else if focusedOpening == Opening(step: stepIndex, primaryTitle: step.primaryTitle) {
                focusedOpening = nil
                focusNewPrimary()
            }
        }
    }

    /// A step's primary button, as the focus sees it: a new step, or a new title
    /// within one, is a new button.
    private struct Opening: Hashable {
        let step: Int
        let primaryTitle: String
    }

    /// Takes the focus from the button that had it, in AppKit as well as SwiftUI:
    /// a fading button left first responder kept its ring, and a replaced one took
    /// the focus back from its successor as it went.
    private func letGoOfFocus() {
        focusedPrimary = nil
        guard activeState == .key else { return }
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    /// Gives the focus to the primary button if it is one the card has not
    /// focused yet. A button the user has tabbed away from keeps its place when
    /// the window comes back to the front.
    private func focusNewPrimary() {
        let opening = Opening(step: stepIndex, primaryTitle: step.primaryTitle)
        guard activeState == .key, isEnabled, focusedOpening != opening else { return }
        focusedOpening = opening
        // On the next turn, when a new step's page, or a new button, is in the window.
        Task { focusedPrimary = opening }
    }

    /// Everything under the picture: the step showing, as one page, and every
    /// other step laid out unseen so that the page area is the tallest step's.
    /// A step change crossfades the page whole, so the buttons go with the words,
    /// and in a still frame: the area's height is the same before and after.
    private var pages: some View {
        OnboardingCardPageLayout {
            page(step, index: stepIndex) {
                if let secondaryTitle = step.secondaryTitle, let onSecondary {
                    Button(secondaryTitle) { withoutAnimationIfKeyPress(onSecondary) }
                        .buttonStyle(.bordered)
                        // A new title is a new button: the glass stays whole.
                        .id(secondaryTitle)
                }
                Button(step.primaryTitle) { withoutAnimationIfKeyPress(onPrimary) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .focused($focusedPrimary, equals: Opening(step: stepIndex, primaryTitle: step.primaryTitle))
                    .id(step.primaryTitle)
            }
            .id(stepIndex)
            .transition(.opacity)

            // The other steps, for their height only: never drawn, pressed, read or focused.
            ForEach(sizingSteps.indices.filter { $0 != stepIndex }, id: \.self) { index in
                let other = sizingSteps[index]
                page(other, index: index) {
                    if let secondaryTitle = other.secondaryTitle {
                        Button(secondaryTitle) {}
                            .buttonStyle(.bordered)
                    }
                    Button(other.primaryTitle) {}
                        .buttonStyle(.borderedProminent)
                }
                .hidden()
                .disabled(true)
                .accessibilityHidden(true)
            }
        }
        // Whether this step change crossfades, for the focus (`body`).
        .transaction(value: stepIndex) { transaction in
            stepChange.crossfades = transaction.animation != nil && !transaction.disablesAnimations
        }
        .animation(stepAnimation, value: stepIndex)
        // The pages' place is the card's; only the crossfade inside it animates.
        // Without the group each view animated its own move when the card's height
        // changed, and the dots slid up from below the card's new edge.
        .geometryGroup()
    }

    /// One step's page: its words and accessory at the top, its dots and buttons
    /// at the bottom of whatever height the page is given.
    private func page(_ step: OnboardingCardStep, index: Int, @ViewBuilder buttons: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Spacing.large) {
                VStack(alignment: .leading, spacing: Spacing.tight) {
                    Text(step.title)
                        .font(.title2.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(step.message)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)

                // None, or a step with none, takes no room.
                if step.showsAccessory {
                    accessory
                }
            }
            .padding(.horizontal, Spacing.small)
            .entering(group: 1, hasEntered: hasEntered)

            Spacer(minLength: Spacing.large)

            HStack(spacing: Spacing.small) {
                pageIndicator(index: index)
                Spacer(minLength: Spacing.large)
                buttons()
            }
            .controlSize(.large)
            .padding([.horizontal, .bottom], Spacing.small)
            .entering(group: 2, hasEntered: hasEntered)
        }
    }

    /// Opaque, and lighter than the window in both appearances, so the card
    /// reads as raised even in dark mode where shadows barely show.
    private var fill: Color {
        scheme == .dark ? Color(nsColor: .windowBackgroundColor).mix(with: .white, by: 0.06) : Color(nsColor: .controlBackgroundColor)
    }

    /// A step change by click crossfades the picture and the page, each with its
    /// own scoped animation and nothing on the card itself. By key press nothing
    /// animates.
    private var stepAnimation: Animation {
        accessibility.fade(Motion.enter(Motion.Duration.menu))
    }

    private var picture: some View {
        Color.clear
            .aspectRatio(Metrics.illustrationAspectRatio, contentMode: .fit)
            .overlay {
                illustration
                    .id(stepIndex)
                    .transition(.opacity)
            }
            .animation(stepAnimation, value: stepIndex)
            .geometryGroup()
            .clipShape(ConcentricRectangle())
            .imageOutline(ConcentricRectangle())
            .accessibilityHidden(true)
    }

    /// Nothing for a card alone: one dot would only say "Step 1 of 1".
    @ViewBuilder private func pageIndicator(index: Int) -> some View {
        if stepCount > 1 {
            HStack(spacing: Spacing.small) {
                ForEach(0..<max(stepCount, 0), id: \.self) { dot in
                    Circle()
                        .fill(.primary)
                        .opacity(dot == index ? 1 : Metrics.restingDotOpacity)
                        .frame(width: Metrics.dot, height: Metrics.dot)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("Step \(index + 1) of \(stepCount)", bundle: .module))
        }
    }
}

extension OnboardingCard where Accessory == EmptyView {
    /// A card that knows every step, whose only controls are its buttons.
    public init(
        steps: [OnboardingCardStep],
        stepIndex: Int,
        onPrimary: @escaping () -> Void,
        onSecondary: (() -> Void)? = nil,
        @ViewBuilder illustration: () -> Illustration
    ) {
        self.init(
            steps: steps, stepIndex: stepIndex, onPrimary: onPrimary, onSecondary: onSecondary,
            illustration: illustration, accessory: { EmptyView() }
        )
    }

    /// A card that knows only the step it shows, whose only controls are its buttons.
    public init(
        title: String,
        message: String,
        stepIndex: Int,
        stepCount: Int,
        primaryTitle: String,
        onPrimary: @escaping () -> Void,
        secondaryTitle: String? = nil,
        onSecondary: (() -> Void)? = nil,
        @ViewBuilder illustration: () -> Illustration
    ) {
        self.init(
            title: title,
            message: message,
            stepIndex: stepIndex,
            stepCount: stepCount,
            primaryTitle: primaryTitle,
            onPrimary: onPrimary,
            secondaryTitle: secondaryTitle,
            onSecondary: onSecondary,
            illustration: illustration,
            accessory: { EmptyView() }
        )
    }
}

extension View {
    fileprivate func entering(group: Int, hasEntered: Bool) -> some View {
        modifier(GroupEntrance(group: group, hasEntered: hasEntered))
    }
}

/// Opacity, a small rise and a blur that clears. Under Reduce Motion the helper
/// returns no delay and only the opacity changes.
private struct GroupEntrance: ViewModifier {
    @Accessibility private var accessibility
    let group: Int
    let hasEntered: Bool

    func body(content: Content) -> some View {
        let moves = !hasEntered && !accessibility.reduceMotion
        content
            .opacity(hasEntered ? 1 : 0)
            .offset(y: moves ? Metrics.entranceRise : 0)
            .blur(radius: moves ? Metrics.entranceBlur : 0)
            .animation(
                accessibility.animation(Motion.enter(Motion.Duration.sheet))
                    .delay(accessibility.staggerDelay(forOnboardingGroup: group)),
                value: hasEntered
            )
    }
}

private nonisolated enum Metrics {
    /// Wide enough for two buttons and the indicator on one line; narrow enough that the message wraps short.
    static let width: CGFloat = 440
    static let illustrationAspectRatio: CGFloat = 16 / 10
    static let dot: CGFloat = 6
    static let restingDotOpacity = 0.25
    /// A small fixed rise, not a slide: the card is already where it belongs.
    static let entranceRise: CGFloat = 8
    static let entranceBlur: CGFloat = 4
    static let contactShadowRadius: CGFloat = 2
    static let contactShadowOffset: CGFloat = 1
    static let ambientShadowRadius: CGFloat = 24
    static let ambientShadowOffset: CGFloat = 12
}
