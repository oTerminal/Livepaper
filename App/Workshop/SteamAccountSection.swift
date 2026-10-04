import DesignSystem
import SwiftUI

/// Settings' Workshop section: the Steam account steamcmd's saved login is
/// under, with Sign Out, which revokes it (steamcmd's `logout`), or Sign In.
struct SteamAccountSection: View {
    @Environment(WorkshopModel.self) private var workshop
    @State private var isConfirmingSignOut = false

    var body: some View {
        Section {
            LabeledContent("Steam account") {
                if let account = workshop.account {
                    Text(account)
                        .textSelection(.enabled)
                } else {
                    Text("Not signed in")
                        .foregroundStyle(.secondary)
                }
            }
            if workshop.account != nil {
                HStack(spacing: Spacing.small) {
                    Button("Sign Out of Steam…") { isConfirmingSignOut = true }
                        .disabled(workshop.isSigningOut)
                    if workshop.isSigningOut {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("Signing out")
                    }
                }
            } else {
                Button("Sign In to Steam…") { workshop.beginSignIn(on: .settings) }
            }
            if let problem = workshop.signOutProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Wallpaper Engine Workshop")
        } footer: {
            Text(
                """
                Workshop items download with your own Steam account, which must own Wallpaper Engine, through Valve’s \
                steamcmd. Livepaper keeps the account’s name, never its password.
                """
            )
        }
        .confirmationDialog("Sign out of Steam?", isPresented: $isConfirmingSignOut) {
            SignOutButtons()
        } message: {
            Text(SteamAccountWords.signOutMessage)
        }
    }
}
