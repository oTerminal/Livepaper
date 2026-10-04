import DesignSystem
import SwiftUI

struct LoginItemRowPage: View {
    @State private var state = LoginItemState.off

    var body: some View {
        StateSection(title: "Off") { row(.off) }
        StateSection(title: "On") { row(.on) }
        StateSection(
            title: "Needs approval",
            note: "The switch shows on, because the request stands. The symbol and the words carry the warning, not the colour."
        ) {
            row(.needsApproval)
        }
        StateSection(title: "Not found", note: "Off and disabled: nothing the switch could do would work.") { row(.notFound) }

        StateSection(
            title: "Interactive",
            note: """
            The switch shows the state it is given. Turning it on here answers “needs approval”; Open System Settings \
            stands in for the user allowing it.
            """
        ) {
            Form {
                LoginItemRow(state: state, appName: "Livepaper") { isOn in
                    state = isOn ? .needsApproval : .off
                } onOpenSystemSettings: {
                    state = .on
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .frame(maxWidth: 480)
        }
    }

    private func row(_ state: LoginItemState) -> some View {
        Form {
            LoginItemRow(state: state, appName: "Livepaper", onChange: { _ in }, onOpenSystemSettings: {})
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(maxWidth: 480)
    }
}
