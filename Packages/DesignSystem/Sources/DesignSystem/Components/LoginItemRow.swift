import SwiftUI

/// What the system says about the app's login item.
public nonisolated enum LoginItemState: Hashable, Sendable, CaseIterable {
    case off
    case on
    /// Registered, but the user has yet to allow it in System Settings.
    case needsApproval
    /// The system cannot find the app to register, usually because it is not in Applications.
    case notFound
}

/// The "Open at Login" setting. It is told the state and never asks the system
/// itself. The switch shows the state it is given, not an optimistic local copy:
/// flipping it only calls `onChange`, and it moves when the caller hands back a
/// new state, so it can never disagree with System Settings. Hand the new state
/// back in the same turn as `onChange` where you can: a switch answered late
/// slides on, back, and on again.
public struct LoginItemRow: View {
    private let state: LoginItemState
    private let appName: String
    private let onChange: (Bool) -> Void
    private let onOpenSystemSettings: () -> Void

    public init(
        state: LoginItemState,
        appName: String,
        onChange: @escaping (Bool) -> Void,
        onOpenSystemSettings: @escaping () -> Void
    ) {
        self.state = state
        self.appName = appName
        self.onChange = onChange
        self.onOpenSystemSettings = onOpenSystemSettings
    }

    private var isOn: Bool {
        state == .on || state == .needsApproval
    }

    public var body: some View {
        // No animation anywhere: the state changes rarely and from outside, and
        // animating the caption in would mean animating the row's height.
        VStack(alignment: .leading, spacing: Spacing.small) {
            toggleAndWarnings
        }
        // The warning appears below while focus stays on the switch, so say it.
        .onChange(of: state) { _, state in
            switch state {
            case .needsApproval:
                announce(approvalMessage)
            case .notFound:
                announce(notFoundMessage)
            case .off, .on:
                break
            }
        }
    }

    private var approvalMessage: String {
        String(localized: "Allow \(appName) in System Settings to finish turning this on.", bundle: .module)
    }

    private var notFoundMessage: String {
        String(localized: "Login item not found. Move \(appName) to the Applications folder and try again.", bundle: .module)
    }

    private func announce(_ message: String) {
        AccessibilityNotification.Announcement(message).post()
    }

    @ViewBuilder private var toggleAndWarnings: some View {
        Group {
            Toggle(isOn: Binding(get: { isOn }, set: { onChange($0) })) {
                Text("Open at Login", bundle: .module)
            }
            .toggleStyle(.switch)
            .disabled(state == .notFound)
            .accessibilityLabel(Text("Open at Login", bundle: .module))
            // A native switch speaks its own on or off and ignores a value given to
            // it, so the warning rides along as the hint.
            .accessibilityHint(spokenHint)

            switch state {
            case .off, .on:
                EmptyView()
            case .needsApproval:
                warning(Text(verbatim: approvalMessage))
                Button(action: onOpenSystemSettings) {
                    Text("Open System Settings…", bundle: .module)
                }
                .padding(.leading, Metrics.captionIndent)
            case .notFound:
                warning(Text(verbatim: notFoundMessage))
            }
        }
    }

    /// "On" alone would mislead while the login item is not yet in effect.
    private var spokenHint: Text {
        switch state {
        case .off, .on: Text(verbatim: "")
        case .needsApproval: Text(verbatim: approvalMessage)
        case .notFound: Text(verbatim: notFoundMessage)
        }
    }

    /// Symbol and words together: the warning never rests on colour alone.
    private func warning(_ text: Text) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.tight) {
            Image(systemName: "exclamationmark.triangle.fill")
                .symbolRenderingMode(.multicolor)
                .foregroundStyle(.yellow)
                .frame(width: Metrics.symbolSlot, alignment: .leading)
                .accessibilityLabel(Text("Warning", bundle: .module))
            text
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
        .accessibilityElement(children: .combine)
    }
}

private nonisolated enum Metrics {
    /// Fixed slot for the warning symbol, so the button below lines up with the caption's text.
    static let symbolSlot: CGFloat = 18
    static let captionIndent: CGFloat = symbolSlot + Spacing.tight
}
