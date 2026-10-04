import DesignSystem
import SwiftUI

struct SetOnDisplayButtonPage: View {
    @State private var state = SetOnDisplayState.idle
    @State private var lastTarget = "nothing yet"
    @State private var run: Task<Void, Never>?

    private let one = [SetOnDisplayTarget(id: "built-in", name: "Built-in Display", isCurrent: true)]
    private let three = [
        SetOnDisplayTarget(id: "built-in", name: "Built-in Display", isCurrent: true),
        SetOnDisplayTarget(id: "studio", name: "Studio Display"),
        SetOnDisplayTarget(id: "lg", name: "LG UltraFine"),
    ]

    var body: some View {
        StateSection(
            title: "Live",
            note: "Click: working for a second, then done, then idle again. The title must not move. Last action: \(lastTarget)."
        ) {
            SetOnDisplayButton(targets: three, state: state) { id in
                lastTarget = id == SetOnDisplayTarget.allID ? "All Displays" : id
                run?.cancel()
                run = Task {
                    state = .working
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled else { return }
                    state = .done
                    try? await Task.sleep(for: .seconds(1.5))
                    guard !Task.isCancelled else { return }
                    state = .idle
                }
            }
        }

        StateSection(title: "One target") {
            SetOnDisplayButton(targets: one) { _ in }
        }

        StateSection(title: "Three targets", note: "The button sets on the first; the menu lists all three and All Displays.") {
            SetOnDisplayButton(targets: three) { _ in }
        }

        StateSection(title: "Long name, narrow inspector", note: "The name truncates; the chevron keeps its size.") {
            SetOnDisplayButton(
                targets: [
                    SetOnDisplayTarget(id: "room", name: "Conference Room Projector, Second Floor East"),
                    SetOnDisplayTarget(id: "built-in", name: "Built-in Display"),
                ]
            ) { _ in }
            .frame(width: 260, alignment: .leading)
        }

        StateSection(title: "Working", note: "A spinner takes the icon's slot and the control is disabled.") {
            GlassEffectContainer {
                HStack(spacing: Spacing.large) {
                    SetOnDisplayButton(targets: one, state: .working) { _ in }
                    SetOnDisplayButton(targets: three, state: .working) { _ in }
                }
            }
        }

        StateSection(title: "Done") {
            GlassEffectContainer {
                HStack(spacing: Spacing.large) {
                    SetOnDisplayButton(targets: one, state: .done) { _ in }
                    SetOnDisplayButton(targets: three, state: .done) { _ in }
                }
            }
        }

        StateSection(title: "Disabled", note: "Disabled by the caller, and with no targets at all.") {
            GlassEffectContainer {
                HStack(spacing: Spacing.large) {
                    SetOnDisplayButton(targets: one) { _ in }
                        .disabled(true)
                    SetOnDisplayButton(targets: three) { _ in }
                        .disabled(true)
                    SetOnDisplayButton(targets: []) { _ in }
                }
            }
        }
    }
}
