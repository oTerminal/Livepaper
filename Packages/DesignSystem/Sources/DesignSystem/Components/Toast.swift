import SwiftUI

/// A brief message that floats above the window's bottom edge. With an undo
/// title it is an undo toast. Present it with `toastHost`, which also gives it
/// Command-Z.
public struct Toast: View {
    private let item: ToastItem
    private let onUndo: () -> Void
    private let onDismiss: () -> Void

    public init(_ item: ToastItem, onUndo: @escaping () -> Void = {}, onDismiss: @escaping () -> Void) {
        self.item = item
        self.onUndo = onUndo
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: Spacing.small) {
            if let systemImage = item.systemImage {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            Text(item.message)
                .lineLimit(2)
            if let undoTitle = item.undoTitle {
                // Tinted text on the toast's glass, never glass on glass.
                // Space on the focused button is a key press: the toast leaves without animating.
                Button { withoutAnimationIfKeyPress(onUndo) } label: {
                    Text(undoTitle)
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                        .padding(.horizontal, Spacing.small)
                        .frame(minHeight: Spacing.minimumHitArea)
                        .contentShape(.interaction, .rect)
                        .contentShape(.focusEffect, .capsule)
                }
                .buttonStyle(.press)
            }
            Button { withoutAnimationIfKeyPress(onDismiss) } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: Spacing.minimumHitArea, height: Spacing.minimumHitArea)
                    // The ring is the end cap's circle, not a square on a capsule.
                    .contentShape(.interaction, .rect)
                    .contentShape(.focusEffect, .circle)
            }
            .buttonStyle(.press)
            .accessibilityLabel(Text("Dismiss", bundle: .module))
        }
        .font(.callout)
        // The dismiss button's own slot pads the trailing end, concentric with the
        // cap. A leading symbol sits 2 pt closer to the edge than text would.
        .padding(.leading, item.systemImage == nil ? Spacing.large : Spacing.large - Spacing.hairline)
        .frame(minHeight: Spacing.minimumHitArea)
        .layerSurface(.popover, in: .capsule)
        .shadow(color: .black.opacity(0.16), radius: 16, y: 6)
        .accessibilityElement(children: .contain)
    }
}

/// An undo toast is a `Toast` whose item has an undo title.
public typealias UndoToast = Toast

extension View {
    /// Shows the presenter's toast over this view's bottom edge and expires it.
    ///
    /// A second toast replaces the first in place: the capsule stays where it
    /// is and its content crossfades, so rapid actions never stack or queue.
    /// The countdown holds while the pointer is over the toast.
    public func toastHost(_ presenter: Binding<ToastPresenter>, onUndo: @escaping (ToastItem.ID) -> Void) -> some View {
        modifier(ToastHost(presenter: presenter, onUndo: onUndo))
    }
}

private struct ToastHost: ViewModifier {
    @Accessibility private var accessibility
    @Binding var presenter: ToastPresenter
    let onUndo: (ToastItem.ID) -> Void
    @State private var isHovered = false
    @AccessibilityFocusState private var isAccessibilityFocused: Bool

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            // The animation is scoped to the toast's own container, so a host
            // that changes in the same transaction (a grid reflowing after a
            // delete) never inherits it.
            ZStack(alignment: .bottom) {
                if let item = presenter.current {
                    toast(item)
                }
            }
            .animation(
                accessibility.animation(
                    presenter.current == nil ? Motion.exit(Motion.Duration.panel) : Motion.enter(Motion.Duration.panel)
                ),
                value: presenter.current?.id
            )
        }
    }

    private func toast(_ item: ToastItem) -> some View {
        Toast(item, onUndo: undo) {
            presenter.send(.dismiss)
        }
        .background {
            if item.undoTitle != nil {
                // Command-Z is a key press, so the toast leaves without animating.
                // Only an undo toast takes it; a plain one leaves the app's Undo alone.
                Button { withoutAnimation(undo) } label: { EmptyView() }
                    .keyboardShortcut("z", modifiers: .command)
                    .hidden()
                    .accessibilityHidden(true)
            }
        }
        // Replacing the item swaps the content, not the toast.
        .contentTransition(.opacity)
        .onHover { isHovered = $0 }
        .accessibilityFocused($isAccessibilityFocused)
        .padding(.bottom, Spacing.extraLarge)
        .transition(transition)
        // Held while the pointer or VoiceOver is on it, so it never goes from under the user.
        .task(id: ExpiryKey(item: item.id, isHeld: isHovered || isAccessibilityFocused)) {
            guard !isHovered, !isAccessibilityFocused else { return }
            try? await Task.sleep(for: ToastPresenter.lifetime)
            guard !Task.isCancelled else { return }
            presenter.send(.expire(item.id))
        }
        .onAppear { announce(item) }
        .onChange(of: item.id) { announce(item) }
        // A view removed from under the pointer is not told the pointer left.
        .onDisappear { isHovered = false }
    }

    private func undo() {
        if case .undo(let id) = presenter.send(.undo) {
            onUndo(id)
        }
    }

    /// Rises a short, fixed distance; never the toast's full height.
    private var transition: AnyTransition {
        accessibility.reduceMotion
            ? .opacity
            : .offset(y: Spacing.medium).combined(with: .scale(scale: Motion.enterScale, anchor: .bottom)).combined(with: .opacity)
    }

    private func announce(_ item: ToastItem) {
        AccessibilityNotification.Announcement(item.message).post()
    }

    private struct ExpiryKey: Equatable {
        let item: ToastItem.ID
        let isHeld: Bool
    }
}
