import SwiftUI

/// Where one import has got to.
public nonisolated enum ImportProgressState: Equatable, Sendable {
    case queued
    /// `fraction` is 0 to 1; `nil` when the length of the work is not known.
    case running(fraction: Double?, detail: String)
    case finished
    case failed(message: String)
}

/// One import in the queue. Every state has the same height and the same
/// columns, so a row never shifts its neighbours as it moves from queued to
/// finished. A failure is said in words and with a symbol, never by colour alone.
public struct ImportProgressRow: View {
    @Accessibility private var accessibility

    private let title: String
    private let poster: Image?
    private let state: ImportProgressState
    private let onCancel: (() -> Void)?
    private let onRetry: (() -> Void)?

    public init(
        title: String,
        poster: Image? = nil,
        state: ImportProgressState,
        onCancel: (() -> Void)? = nil,
        onRetry: (() -> Void)? = nil
    ) {
        self.title = title
        self.poster = poster
        self.state = state
        self.onCancel = onCancel
        self.onRetry = onRetry
    }

    public var body: some View {
        HStack(spacing: Spacing.medium) {
            HStack(spacing: Spacing.medium) {
                thumbnail
                VStack(alignment: .leading, spacing: Spacing.tight) {
                    Text(title)
                        .font(.callout)
                        .lineLimit(1)
                        // Titles are often file names; keep the end that tells them apart.
                        .truncationMode(.middle)
                    progress
                }
            }
            .accessibilityElement(children: .ignore)
            // File first, then its progress, as one label: VoiceOver speaks a value before the label.
            .accessibilityLabel(Text(verbatim: spokenValue.isEmpty ? title : "\(title), \(spokenValue)"))

            trailing
        }
    }

    // MARK: Progress

    private var progress: some View {
        // The bar and its caption stay in the layout in every state, so they fix the
        // row's height; a failure's message is laid over the space they hold.
        VStack(alignment: .leading, spacing: Spacing.tight) {
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .labelsHidden()
                // A new bar when it learns or loses its length: switched in place, AppKit's
                // indeterminate sweep ran on for seconds into Finished.
                .id(fraction == nil)
            HStack(spacing: Spacing.small) {
                Text(detail)
                    .lineLimit(1)
                Spacer(minLength: 0)
                // As wide as "100%" at any text size, so the detail never moves.
                Text(1.0, format: .percent.precision(.fractionLength(0)))
                    .hidden()
                    .overlay(alignment: .trailing) {
                        if let fraction, isRunning {
                            Text(fraction, format: .percent.precision(.fractionLength(0)))
                        }
                    }
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.secondary)
        }
        .opacity(failureMessage == nil ? 1 : 0)
        .overlay(alignment: .leading) {
            if let failureMessage {
                Label {
                    Text(failureMessage)
                        .lineLimit(2)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(.caption)
                .foregroundStyle(.red)
                .help(failureMessage)
                .transition(.opacity)
            }
        }
        // The bar gives way to the message as one crossfade, in step with the trailing symbol.
        .animation(accessibility.fade(Motion.enter(Motion.Duration.menu)), value: failureMessage == nil)
    }

    private var isRunning: Bool {
        if case .running = state { true } else { false }
    }

    /// What the bar shows. `nil` is indeterminate.
    private var fraction: Double? {
        switch state {
        case .queued, .failed: 0
        case .running(let fraction, _): fraction.map { min(max($0, 0), 1) }
        case .finished: 1
        }
    }

    private var detail: String {
        switch state {
        case .queued: String(localized: "Waiting", bundle: .module)
        case .running(_, let detail): detail
        case .finished: String(localized: "Finished", bundle: .module)
        case .failed: ""
        }
    }

    private var failureMessage: String? {
        if case .failed(let message) = state { message } else { nil }
    }

    private var spokenValue: String {
        switch state {
        case .queued, .finished:
            detail
        case .running(_, let detail):
            [fraction?.formatted(.percent.precision(.fractionLength(0))), detail]
                .compactMap(\.self)
                .joined(separator: ", ")
        case .failed(let message):
            [String(localized: "Failed", bundle: .module), message].joined(separator: ", ")
        }
    }

    // MARK: Thumbnail

    private var thumbnail: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
        return Color.clear
            .frame(width: Metrics.thumbnailSize.width, height: Metrics.thumbnailSize.height)
            .overlay {
                if let poster {
                    poster
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Rectangle().fill(.quaternary)
                        Image(systemName: "film")
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .clipShape(shape)
            .imageOutline(shape)
    }

    // MARK: Trailing

    /// One image in every state, so the symbol can replace itself rather than be swapped out.
    private var trailing: some View {
        let kind = TrailingKind(state: state, canCancel: onCancel != nil, canRetry: onRetry != nil)
        return TrailingButton(kind: kind) {
            switch kind {
            case .cancel: onCancel?()
            case .retry: onRetry?()
            case .finished, .none: break
            }
        }
    }
}

private nonisolated enum TrailingKind: Equatable {
    case cancel, retry, finished, none

    init(state: ImportProgressState, canCancel: Bool, canRetry: Bool) {
        switch state {
        case .queued, .running: self = canCancel ? .cancel : .none
        case .failed: self = canRetry ? .retry : .none
        case .finished: self = .finished
        }
    }

    var symbol: String {
        switch self {
        case .cancel, .none: "xmark.circle.fill"
        case .retry: "arrow.clockwise.circle.fill"
        case .finished: "checkmark.circle.fill"
        }
    }

    var isButton: Bool {
        self == .cancel || self == .retry
    }
}

private struct TrailingButton: View {
    @Accessibility private var accessibility
    @State private var isHovered = false

    let kind: TrailingKind
    let action: () -> Void

    var body: some View {
        Button {
            withoutAnimationIfKeyPress(action)
        } label: {
            Image(systemName: kind.symbol)
                .font(.title3)
                .contentTransition(accessibility.symbolReplace)
                .foregroundStyle(style)
                .opacity(kind == .none ? 0 : 1)
                .frame(minWidth: Spacing.minimumHitArea, minHeight: Spacing.minimumHitArea)
                // A round glyph in a square slot: the ring is round, the target square.
                .contentShape(.interaction, .rect)
                .contentShape(.focusEffect, .circle)
        }
        .buttonStyle(.press)
        .disabled(!kind.isButton)
        .onHover { isHovered = $0 }
        .animation(accessibility.animation(Motion.Spring.ui), value: kind)
        .animation(
            accessibility.fade(isHovered ? Motion.enter(Motion.Duration.hover) : Motion.exit(Motion.Duration.hover)),
            value: isHovered
        )
        .accessibilityLabel(label)
        // The tick is already in the row's value; only a real button is worth a stop.
        .accessibilityHidden(!kind.isButton)
        .help(label)
    }

    private var style: AnyShapeStyle {
        if kind == .finished {
            AnyShapeStyle(.green)
        } else if isHovered {
            AnyShapeStyle(.primary)
        } else {
            AnyShapeStyle(.secondary)
        }
    }

    private var label: Text {
        switch kind {
        case .cancel: Text("Cancel Import", bundle: .module)
        case .retry: Text("Retry Import", bundle: .module)
        case .finished, .none: Text(verbatim: "")
        }
    }
}

private nonisolated enum Metrics {
    /// 16:10, as tall as the trailing button's hit area so the row has one height.
    static let thumbnailSize = CGSize(width: 64, height: Spacing.minimumHitArea)
}
