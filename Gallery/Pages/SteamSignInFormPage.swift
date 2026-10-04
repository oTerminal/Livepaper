import DesignSystem
import SwiftUI

struct SteamSignInFormPage: View {
    @State private var account = ""
    @State private var password = ""
    @State private var code = ""
    @State private var step = SteamSignInStep.credentials(problem: nil)

    var body: some View {
        StateSection(
            title: "Live",
            note: "Sign In walks the steps as Steam would answer: setting up, then a code, then signing in. Cancel starts again."
        ) {
            SteamSignInForm(
                step: step, account: $account, password: $password, code: $code,
                onSignIn: {
                    step = .working(detail: "Signing in to Steam", fraction: nil)
                    after { step = .code(.app, problem: nil) }
                },
                onSubmitCode: {
                    step = .working(detail: "Signing in to Steam", fraction: nil)
                    after { step = .approval }
                },
                onCancel: { step = .credentials(problem: nil) }
            )
            .sheetPlate()
        }

        StateSection(title: "Credentials", note: "Sign In is enabled once both fields have something in them.") {
            HStack(alignment: .top, spacing: Spacing.extraLarge) {
                form(.credentials(problem: nil), account: "", password: "")
                form(
                    .credentials(problem: "Steam did not accept that account name and password."),
                    account: "someone",
                    password: "hunter2"
                )
            }
        }

        StateSection(title: "Steam Guard", note: "A code from the email, a code from the Steam Mobile app, and a code Steam refused.") {
            Grid(alignment: .topLeading, horizontalSpacing: Spacing.extraLarge, verticalSpacing: Spacing.extraLarge) {
                GridRow {
                    form(.code(.email, problem: nil))
                    form(.code(.app, problem: nil), code: "F7K2Q")
                }
                GridRow {
                    form(
                        .code(.app, problem: "Steam did not accept that code. Codes last a short while, so use the newest one."),
                        code: "F7K2Q"
                    )
                }
            }
        }

        StateSection(title: "Waiting", note: "Approval in the Steam Mobile app; setting up Steam’s download tool, known length and not.") {
            Grid(alignment: .topLeading, horizontalSpacing: Spacing.extraLarge, verticalSpacing: Spacing.extraLarge) {
                GridRow {
                    form(.approval)
                    form(.working(detail: "Updating Steam’s download tool", fraction: 0.43))
                }
                GridRow {
                    form(.working(detail: "Signing in to Steam", fraction: nil))
                }
            }
        }
    }

    private func form(_ step: SteamSignInStep, account: String = "someone", password: String = "", code: String = "") -> some View {
        SteamSignInForm(
            step: step, account: .constant(account), password: .constant(password), code: .constant(code),
            onSignIn: {}, onSubmitCode: {}, onCancel: {}
        )
        .sheetPlate()
    }

    private func after(_ change: @escaping () -> Void) {
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            change()
        }
    }
}

extension View {
    /// Drawn on a sheet's own background, as the app presents it.
    fileprivate func sheetPlate() -> some View {
        background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: Radius.panel))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.panel).strokeBorder(.separator)
            }
    }
}
