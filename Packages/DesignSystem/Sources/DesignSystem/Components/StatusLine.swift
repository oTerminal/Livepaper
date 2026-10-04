import SwiftUI

/// What the status line is saying.
public nonisolated enum StatusLineStatus: Hashable, Sendable {
    /// Nothing happening, such as "42 wallpapers".
    case idle(String)
    /// Work in progress, such as "Importing 2 of 5".
    case working(String)
    /// The wallpaper service has stopped answering. The words are the package's.
    case serviceNotResponding

    fileprivate enum Kind: Hashable {
        case idle, working, serviceNotResponding
    }

    fileprivate var kind: Kind {
        switch self {
        case .idle: .idle
        case .working: .working
        case .serviceNotResponding: .serviceNotResponding
        }
    }

    /// What the line says, and VoiceOver with it: a sentence without its full
    /// stop, as the caller's words are ("Livepaper is not your wallpaper").
    public var words: String {
        switch self {
        case .idle(let words), .working(let words): words
        case .serviceNotResponding: String(localized: "Wallpaper service not responding", bundle: .module)
        }
    }
}

/// The single line at the bottom of the window, and the one place a wallpaper
/// service that has stopped responding is reported. The line keeps one height in
/// every status, and only a change of kind crossfades: a count ticking up inside
/// `.working` swaps in place, because it changes many times a second. The
/// crossfade happens inside the line, so when the layout moves the line in the
/// same change, the words it is leaving go with it.
public struct StatusLine: View {
    @Accessibility private var accessibility

    private let status: StatusLineStatus
    private let onRestart: () -> Void

    public init(status: StatusLineStatus, onRestart: @escaping () -> Void) {
        self.status = status
        self.onRestart = onRestart
    }

    public var body: some View {
        ZStack(alignment: .leading) {
            content
                .id(status.kind)
                .transition(.opacity)
        }
        .font(.callout)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .lineLimit(1)
        // Tall enough for the Restart button's hit area, always, so the window's
        // content never shifts when the service goes away.
        .frame(maxWidth: .infinity, minHeight: Spacing.minimumHitArea, alignment: .leading)
        // One scoped animation: a crossfade, so Reduce Motion leaves it alone and a
        // caller's `withoutAnimation` still silences it.
        .animation(accessibility.fade(Motion.enter(Motion.Duration.hover)), value: status.kind)
        // The line's place is its container's, and moves at once: without the group
        // the words it was leaving faded out where the line had been, over whatever
        // the layout had moved there (the popover's recent wallpapers, when an
        // import grew a display's card).
        .geometryGroup()
        .onChange(of: status.kind) { _, kind in
            guard kind == .serviceNotResponding else { return }
            AccessibilityNotification.Announcement(status.words).post()
        }
    }

    @ViewBuilder private var content: some View {
        switch status {
        case .idle(let text):
            Text(text)
        case .working(let text):
            HStack(spacing: Spacing.small) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text(text)
            }
            .accessibilityElement(children: .combine)
        case .serviceNotResponding:
            HStack(spacing: Spacing.small) {
                // A static symbol and words: never colour or motion alone.
                Label {
                    Text(status.words)
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .foregroundStyle(.yellow)
                        .accessibilityLabel(Text("Warning", bundle: .module))
                }
                .accessibilityElement(children: .combine)
                CompactTextButton(title: Text("Restart", bundle: .module), action: onRestart)
            }
        }
    }
}

/// Looks like a small bordered button; its hit area is the full height of the line.
