import SwiftUI

/// Press feedback: a control shrinks slightly on pointer down, so the response
/// lands before the action does.
public nonisolated enum Press {
    /// Always 0.96. Anything under 0.95 reads as exaggerated.
    public static let pressedScale: CGFloat = 0.96
    /// What a control that does not move does instead.
    public static let pressedOpacity = 0.7

    /// The scale of a control. `isStatic` opts out where movement would distract.
    public static func scale(isPressed: Bool, isStatic: Bool = false) -> CGFloat {
        isPressed && !isStatic ? pressedScale : 1
    }

    /// The opacity of a control. Only a static control dims: one that scales
    /// has already acknowledged the press.
    public static func opacity(isPressed: Bool, isStatic: Bool = false) -> Double {
        isPressed && isStatic ? pressedOpacity : 1
    }
}

/// Applies `Press` to any button label. The press lands at once and the release
/// eases out, so a quick click still shows. Under Reduce Motion every control
/// is static: it dims rather than shrinks.
public struct PressButtonStyle: ButtonStyle {
    private let isStatic: Bool

    public init(isStatic: Bool = false) {
        self.isStatic = isStatic
    }

    public func makeBody(configuration: Configuration) -> some View {
        PressFeedback(configuration: configuration, isStatic: isStatic)
    }
}

/// A view of its own, so that it can read the accessibility settings.
private struct PressFeedback: View {
    @Accessibility private var accessibility
    let configuration: ButtonStyleConfiguration
    let isStatic: Bool

    var body: some View {
        let isStatic = isStatic || accessibility.reduceMotion
        configuration.label
            .scaleEffect(Press.scale(isPressed: configuration.isPressed, isStatic: isStatic))
            .opacity(Press.opacity(isPressed: configuration.isPressed, isStatic: isStatic))
            .animation(
                configuration.isPressed ? nil : accessibility.fade(Motion.enter(Motion.Duration.press)),
                value: configuration.isPressed
            )
    }
}

extension ButtonStyle where Self == PressButtonStyle {
    /// Scale 0.96 on pointer down.
    public static var press: PressButtonStyle { PressButtonStyle() }
}
