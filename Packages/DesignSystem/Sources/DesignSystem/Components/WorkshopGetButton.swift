import SwiftUI

public nonisolated enum WorkshopGetState: Hashable, Sendable {
    case idle
    /// Being downloaded or imported.
    case working
    /// Handed to the import.
    case done
    /// Nothing to get here, or nothing Livepaper can take. The reason is the tooltip and what VoiceOver reads.
    case unavailable(reason: String)
}

/// The Workshop window's primary action: gets the item whose page is open
/// into the library. Built as SetOnDisplayButton is: one prominent glass button
/// whose icon, spinner and checkmark share a fixed slot, so the title never
/// moves between states. Unavailable is disabled, with the reason as its tooltip.
public struct WorkshopGetButton: View {
    @Accessibility private var accessibility

    private let state: WorkshopGetState
    private let action: () -> Void

    public init(state: WorkshopGetState, action: @escaping () -> Void) {
        self.state = state
        self.action = action
    }

    public var body: some View {
        Button {
            // A key press on the focused button must not animate the state it starts.
            withoutAnimationIfKeyPress(action)
        } label: {
            HStack(spacing: Spacing.small) {
                iconSlot
                Text("Get", bundle: .module)
            }
            .lineLimit(1)
            // Icon-side padding is text-side padding less 2 pt.
            .padding(.leading, -Spacing.hairline)
        }
        .buttonStyle(.glassProminent)
        .disabled(!isEnabled)
        .help(help)
        .accessibilityLabel(Text("Get", bundle: .module))
        .accessibilityValue(value)
    }

    private var isEnabled: Bool {
        state == .idle || state == .done
    }

    private var iconSlot: some View {
        ZStack {
            // Always present, so idle to done is a symbol replace, not an insertion.
            Image(systemName: state == .done ? "checkmark" : "arrow.down")
                .contentTransition(accessibility.symbolReplace)
                .opacity(state == .working ? 0 : 1)
            if state == .working {
                ProgressView()
                    .controlSize(.small)
                    .transition(.opacity)
            }
        }
        .frame(width: Metrics.iconSlot, height: Metrics.iconSlot)
        .animation(accessibility.fade(Motion.enter(Motion.Duration.hover)), value: state)
        .accessibilityHidden(true)
    }

    private var help: Text {
        switch state {
        case .idle: Text("Download this item from Steam into the library", bundle: .module)
        case .working: Text("Getting this item", bundle: .module)
        case .done: Text("This item has gone to the library", bundle: .module)
        case .unavailable(let reason): Text(verbatim: reason)
        }
    }

    private var value: Text {
        switch state {
        case .idle: Text(verbatim: "")
        case .working: Text("Getting", bundle: .module)
        case .done: Text("Done", bundle: .module)
        case .unavailable(let reason): Text(verbatim: reason)
        }
    }
}

private nonisolated enum Metrics {
    /// A small `ProgressView` is 16 pt; the symbols fit the same square.
    static let iconSlot: CGFloat = 16
}
