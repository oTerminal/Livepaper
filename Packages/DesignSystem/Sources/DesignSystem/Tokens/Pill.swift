import SwiftUI

/// The plain fill that marks what is chosen inside a control on glass:
/// FitModePicker's selection pill and LabelToggle's on state. `primary`, so it
/// is never glass on glass and reads in either appearance; stronger under
/// Increase Contrast. One definition, so the two can never drift apart.
nonisolated enum Pill {
    static let opacity = 0.14
    static let increasedContrastOpacity = 0.3

    static func fill(increaseContrast: Bool) -> Color {
        Color.primary.opacity(increaseContrast ? increasedContrastOpacity : opacity)
    }
}
