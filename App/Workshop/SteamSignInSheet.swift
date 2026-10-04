import DesignSystem
import SwiftUI

extension View {
    /// The sign-in sheet, on this window when the sign-in was asked for from it.
    func steamSignInSheet(on host: SignInHost) -> some View {
        modifier(SteamSignInSheetPresenter(host: host))
    }
}

private struct SteamSignInSheetPresenter: ViewModifier {
    @Environment(WorkshopModel.self) private var workshop
    let host: SignInHost

    func body(content: Content) -> some View {
        content.sheet(
            isPresented: Binding {
                workshop.signIn != nil && workshop.signInHost == host
            } set: { isPresented in
                if !isPresented { workshop.cancelSignIn() }
            }
        ) {
            SteamSignInSheet()
        }
    }
}

/// The sheet: `SteamSignInForm` on the model's step. The password and the
/// code are in this sheet's fields and in the one sign-in they are handed to;
/// closing the sheet lets them go.
private struct SteamSignInSheet: View {
    @Environment(WorkshopModel.self) private var workshop
    @State private var account = ""
    @State private var password = ""
    @State private var code = ""

    var body: some View {
        SteamSignInForm(
            step: workshop.signIn ?? .credentials(problem: nil),
            account: $account,
            password: $password,
            code: $code,
            onSignIn: { workshop.submitSignIn(account: account, password: password) },
            onSubmitCode: {
                workshop.submitCode(code)
                code = ""
            },
            onCancel: { workshop.cancelSignIn() }
        )
        .onAppear { account = workshop.account ?? "" }
    }
}

/// What the sign-out confirmations say, in Settings and in the Workshop window.
enum SteamAccountWords {
    static let signOutMessage = "Steam’s download tool forgets its saved login. Getting a Workshop item then asks you to sign in again."
}

/// The sign-out confirmation's buttons.
struct SignOutButtons: View {
    @Environment(WorkshopModel.self) private var workshop

    var body: some View {
        Button("Sign Out", role: .destructive) { workshop.signOut() }
        Button("Cancel", role: .cancel) {}
    }
}
