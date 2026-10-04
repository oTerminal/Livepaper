import AppKit
import SwiftUI

/// A floating glass panel that grows out of the control that opened it. Its
/// content sits on the glass, so nothing inside it may be glass itself.
public struct GlassPopover<Content: View>: View {
    private let contentPadding: CGFloat
    private let content: Content

    /// `contentPadding` is what the corners of the content are concentric to:
    /// with the default 12 pt an 8 pt control fits, and cards of `Radius.card`
    /// want `Spacing.tight` (20 = 16 + 4).
    public init(contentPadding: CGFloat = Spacing.medium, @ViewBuilder content: () -> Content) {
        self.contentPadding = contentPadding
        self.content = content()
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: Radius.panel, style: .continuous)
        content
            .padding(contentPadding)
            // Children draw concentric corners against the panel's.
            .containerShape(shape)
            .layerSurface(.popover, in: shape)
            .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
    }
}

extension AnyTransition {
    /// Scale from 0.96 with opacity, anchored at the trigger. Under Reduce
    /// Motion the movement goes and the fade stays.
    public static func glassPopover(anchor: UnitPoint, reduceMotion: Bool) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: Motion.enterScale, anchor: anchor).combined(with: .opacity)
    }
}

extension View {
    /// Presents `content` in a `GlassPopover` attached to this view's `edge`.
    ///
    /// A click opens it with motion: `Motion.Duration.popover` in, 0.7x out. To
    /// open it from a key press or a hotkey, change `isPresented` inside
    /// `withoutAnimation`. A click outside closes it, as does Escape, which
    /// being a key press does so without animation.
    public func glassPopover(
        isPresented: Binding<Bool>,
        edge: VerticalEdge = .bottom,
        alignment: HorizontalAlignment = .center,
        contentPadding: CGFloat = Spacing.medium,
        @ViewBuilder content: @escaping () -> some View
    ) -> some View {
        modifier(
            GlassPopoverPresentation(
                isPresented: isPresented,
                edge: edge,
                alignment: alignment,
                contentPadding: contentPadding,
                popover: content
            )
        )
    }
}

private struct GlassPopoverPresentation<Popover: View>: ViewModifier {
    @Accessibility private var accessibility
    @Binding var isPresented: Bool
    let edge: VerticalEdge
    let alignment: HorizontalAlignment
    let contentPadding: CGFloat
    let popover: () -> Popover

    @State private var triggerFrame = CGRect.zero
    @State private var popoverFrame = CGRect.zero
    @State private var monitor: Any?
    @AccessibilityFocusState private var isPopoverFocused: Bool

    /// The popover's edge that touches the trigger, which is where it grows from.
    private var anchor: UnitPoint {
        let x: CGFloat = switch alignment {
        case .leading: 0
        case .trailing: 1
        default: 0.5
        }
        return UnitPoint(x: x, y: edge == .bottom ? 0 : 1)
    }

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: { triggerFrame = $0 })
            .overlay(alignment: Alignment(horizontal: alignment, vertical: edge == .bottom ? .bottom : .top)) {
                // Zero-sized, so the popover hangs off the trigger's edge without
                // resizing it. The animation lives here, on the popover's own
                // container: the trigger is the caller's and never inherits it.
                Color.clear
                    .frame(width: 0, height: 0)
                    .overlay(alignment: Alignment(horizontal: alignment, vertical: edge == .bottom ? .top : .bottom)) {
                        if isPresented {
                            presentedPopover
                        }
                    }
                    .animation(
                        accessibility.animation(isPresented ? Motion.enter(Motion.Duration.popover) : Motion.exit(Motion.Duration.popover)),
                        value: isPresented
                    )
            }
            .onChange(of: isPresented, initial: true) { _, isPresented in
                if isPresented {
                    startWatching()
                    isPopoverFocused = true
                } else {
                    stopWatching()
                }
            }
            .onDisappear(perform: stopWatching)
    }

    private var presentedPopover: some View {
        GlassPopover(contentPadding: contentPadding, content: popover)
            .fixedSize()
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }, action: { popoverFrame = $0 })
            // Modal only while presented over other content: the trait hides
            // everything else from VoiceOver, so the panel itself never carries it.
            .accessibilityAddTraits(.isModal)
            .accessibilityFocused($isPopoverFocused)
            .padding(edge == .bottom ? .top : .bottom, Spacing.small)
            .transition(.glassPopover(anchor: anchor, reduceMotion: accessibility.reduceMotion))
    }

    /// Escape and a click outside both close the popover, wherever keyboard
    /// focus happens to be: a click on a button does not always move it.
    private func startWatching() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { event in
            if event.type == .keyDown {
                guard event.keyCode == KeyCode.escape else { return event }
                withoutAnimation { isPresented = false }
                return nil
            }
            // The trigger toggles the popover itself; a click inside is the popover's.
            // Frames are in the host window's space, so a click in another window is outside by definition.
            let location = Self.location(of: event)
            let isElsewhere = event.window != NSApp.keyWindow && event.window != nil
            if isElsewhere || (!triggerFrame.contains(location) && !popoverFrame.contains(location)) {
                isPresented = false
            }
            return event
        }
    }

    private func stopWatching() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    /// The click in SwiftUI's global space, which has its origin at the top left of the window.
    private static func location(of event: NSEvent) -> CGPoint {
        let height = event.window?.contentView?.bounds.height ?? 0
        return CGPoint(x: event.locationInWindow.x, y: height - event.locationInWindow.y)
    }
}

private nonisolated enum KeyCode {
    static let escape: UInt16 = 53
}
