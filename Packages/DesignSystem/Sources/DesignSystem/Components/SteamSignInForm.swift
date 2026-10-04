import SwiftUI

/// Where a sign-in to Steam has got to.
public nonisolated enum SteamSignInStep: Hashable, Sendable {
    /// The account name and password. `problem` says why the last try did not work.
    case credentials(problem: String?)
    /// A Steam Guard code, from the email Steam sent or from the Steam Mobile app.
    case code(SteamGuardCode, problem: String?)
    /// Waiting for the user to approve the sign-in in the Steam Mobile app.
    case approval
    /// Setting Steam's download tool up, or signing in. `fraction` nil is indeterminate.
    case working(detail: String, fraction: Double?)
}

/// Where the Steam Guard code comes from.
public nonisolated enum SteamGuardCode: Hashable, Sendable {
    case email
    case app
}

/// The sign-in sheet's content: the account name and password, then whatever
/// Steam Guard asks, a code or an approval in the Steam Mobile app. It is told
/// the step and holds nothing itself: the fields are the caller's bindings, and
/// what happens to them is the caller's.
///
/// No motion: each step comes from Steam's answer, not from the user's hand,
/// and the sheet's height snaps to the step's. A problem is a symbol and words
/// in red, and is announced, as are the approval and the code steps, since
/// focus does not move to them by itself.
public struct SteamSignInForm: View {
    private let step: SteamSignInStep
    @Binding private var account: String
    @Binding private var password: String
    @Binding private var code: String
    private let onSignIn: () -> Void
    private let onSubmitCode: () -> Void
    private let onCancel: () -> Void
    @FocusState private var focus: Field?

    private enum Field: Hashable {
        case account, password, code
    }

    public init(
        step: SteamSignInStep,
        account: Binding<String>,
        password: Binding<String>,
        code: Binding<String>,
        onSignIn: @escaping () -> Void,
        onSubmitCode: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.step = step
        _account = account
        _password = password
        _code = code
        self.onSignIn = onSignIn
        self.onSubmitCode = onSubmitCode
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            header
            content
            buttons
        }
        .padding(Spacing.extraLarge)
        .frame(width: Metrics.width)
        .onAppear { focusFirstField() }
        .onChange(of: step) { _, step in
            focusFirstField()
            announce(step)
        }
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .top, spacing: Spacing.medium) {
            Image(systemName: "person.badge.key")
                .symbolRenderingMode(.hierarchical)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .frame(width: Metrics.symbolSlot)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Spacing.tight) {
                Text("Sign In to Steam", bundle: .module)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Text(
                    """
                    Livepaper downloads Workshop items with your own Steam account, which must own Wallpaper Engine. \
                    Your password goes to Steam’s download tool for this sign-in, and Livepaper never keeps it.
                    """,
                    bundle: .module
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .credentials(let problem):
            Form {
                TextField(text: $account) { Text("Account name", bundle: .module) }
                    .textContentType(.username)
                    .focused($focus, equals: .account)
                SecureField(text: $password) { Text("Password", bundle: .module) }
                    .textContentType(.password)
                    .focused($focus, equals: .password)
            }
            .formStyle(.columns)
            .disableAutocorrection(true)
            problemLine(problem)

        case .code(let source, let problem):
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text(source == .email ? codeFromEmail : codeFromApp)
                    .fixedSize(horizontal: false, vertical: true)
                TextField(text: $code, prompt: Text("Code", bundle: .module)) { Text("Steam Guard code", bundle: .module) }
                    .font(.title3.monospaced())
                    .textContentType(.oneTimeCode)
                    .disableAutocorrection(true)
                    .frame(width: Metrics.codeFieldWidth)
                    .focused($focus, equals: .code)
            }
            problemLine(problem)

        case .approval:
            HStack(alignment: .firstTextBaseline, spacing: Spacing.medium) {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: Metrics.symbolSlot)
                VStack(alignment: .leading, spacing: Spacing.tight) {
                    Text(approvalMessage)
                    Text("Livepaper carries on once you have approved it.", bundle: .module)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)

        case .working(let detail, let fraction):
            VStack(alignment: .leading, spacing: Spacing.tight) {
                ProgressView(value: fraction)
                    .progressViewStyle(.linear)
                    // A new bar when it learns or loses its length, as ImportProgressRow's.
                    .id(fraction == nil)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: detail))
            .accessibilityValue(Text(fraction.map { $0.formatted(.percent.precision(.fractionLength(0))) } ?? ""))
        }
    }

    private var buttons: some View {
        HStack(spacing: Spacing.small) {
            Spacer()
            Button(role: .cancel) {
                withoutAnimationIfKeyPress(onCancel)
            } label: {
                Text("Cancel", bundle: .module)
            }
            .keyboardShortcut(.cancelAction)
            switch step {
            case .credentials:
                Button {
                    withoutAnimationIfKeyPress(onSignIn)
                } label: {
                    Text("Sign In", bundle: .module)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(account.isEmpty || password.isEmpty)
            case .code:
                Button {
                    withoutAnimationIfKeyPress(onSubmitCode)
                } label: {
                    Text("Continue", bundle: .module)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(code.isEmpty)
            case .approval, .working:
                EmptyView()
            }
        }
    }

    /// Symbol and words together, in red: never colour alone.
    @ViewBuilder private func problemLine(_ problem: String?) -> some View {
        if let problem {
            Label {
                Text(verbatim: problem)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "exclamationmark.triangle.fill")
            }
            .font(.callout)
            .foregroundStyle(.red)
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: Words

    private var codeFromEmail: String {
        String(localized: "Steam has emailed a code to the account’s address. Enter it here.", bundle: .module)
    }

    private var codeFromApp: String {
        String(localized: "Enter the code the Steam Mobile app shows for this account.", bundle: .module)
    }

    private var approvalMessage: String {
        String(localized: "Approve the sign-in in the Steam Mobile app on your phone.", bundle: .module)
    }

    // MARK: Focus and announcements

    private func focusFirstField() {
        switch step {
        case .credentials: focus = account.isEmpty ? .account : .password
        case .code: focus = .code
        case .approval, .working: focus = nil
        }
    }

    private func announce(_ step: SteamSignInStep) {
        let message: String? = switch step {
        case .credentials(let problem?), .code(_, let problem?): problem
        case .code(let source, nil): source == .email ? codeFromEmail : codeFromApp
        case .approval: approvalMessage
        case .credentials(nil), .working: nil
        }
        if let message {
            AccessibilityNotification.Announcement(message).post()
        }
    }
}

private nonisolated enum Metrics {
    /// Room for the sentence under the title on three lines, and a long account name.
    static let width: CGFloat = 440
    /// The header's symbol, and the approval's spinner under it, share a column.
    static let symbolSlot: CGFloat = 40
    /// Five characters of a Steam Guard code at title size, with room to spare.
    static let codeFieldWidth: CGFloat = 140
}
