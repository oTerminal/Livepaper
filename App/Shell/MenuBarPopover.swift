import AppKit
import DesignSystem
import SwiftUI

/// The glass popover under the menu-bar item.
///
/// A borderless, transparent, non-activating panel holds a SwiftUI root that
/// draws `GlassPopover` and runs its enter and exit as the component's own
/// presentation does for a SwiftUI trigger: from the edge that touches the item,
/// `Motion.Duration.popover` in, 0.7x out, opacity only under Reduce Motion. A
/// click outside closes it with motion; Escape, a key press, without. The panel
/// never activates the app, so the app the user was in stays frontmost.
final class MenuBarPopover: NSObject, NSWindowDelegate {
    private let presentation = PopoverPresentation()
    private let panel = PopoverPanel()
    /// The item's button: a click on it is the item's own toggle, never a click outside.
    private weak var anchor: NSStatusBarButton?
    private var monitors: [Any] = []
    /// Moves on with every open and close, so an exit that finishes after a
    /// reopen leaves the panel alone.
    private var generation = 0

    init(anchor: NSStatusBarButton, options: LaunchOptions, contentPadding: CGFloat, content: some View) {
        self.anchor = anchor
        super.init()
        presentation.accessibility = .system(overriding: options.overrides)
        let root = PopoverRoot(presentation: presentation, contentPadding: contentPadding, content: content)
            .launchOptions(options)
        let hostingView = NSHostingView(rootView: root)
        // The panel follows the popover's size, not the other way round.
        hostingView.sizingOptions = []
        panel.contentView = hostingView
        panel.appearance = options.nsAppearance
        panel.delegate = self
        // A size is reported from inside SwiftUI's layout. Moving the panel there laid
        // it out again from inside that layout, which AppKit refuses; with AppKit
        // views in the popover (the recents' scroll view, the playlist pickers) it
        // went on into a constraints loop that crashed the app on open. The next turn
        // of the main queue is soon enough: `open` places the panel itself.
        presentation.sizeChanged = { [weak self] in
            Task { @MainActor in self?.place() }
        }
    }

    var isShown: Bool { presentation.isPresented }

    func toggle(animated: Bool) {
        if isShown { close(animated: animated) } else { open(animated: animated) }
    }

    func open(animated: Bool) {
        guard !isShown else { return }
        generation += 1
        run(animated: animated, entering: true) { presentation.isPresented = true }
        // The popover is laid out now, so the panel is placed before its first frame is drawn.
        panel.contentView?.layoutSubtreeIfNeeded()
        place()
        panel.orderFrontRegardless()
        panel.makeKey()
        // No control starts focused, as in a menu: with keyboard navigation on, the
        // first one (a card's playlist picker) would open ringed as if chosen. Tab
        // goes in from here, and Escape closes wherever focus is.
        panel.makeFirstResponder(nil)
        anchor?.highlight(true)
        startWatching()
    }

    func close(animated: Bool) {
        guard isShown else { return }
        generation += 1
        let closing = generation
        stopWatching()
        anchor?.highlight(false)
        run(animated: animated, entering: false) {
            presentation.isPresented = false
        } completion: { [weak self] in
            guard let self, closing == generation else { return }
            panel.orderOut(nil)
        }
    }

    // MARK: Motion

    /// Runs the change with the popover's motion, resolved through the design
    /// system's accessibility settings as the component resolves it.
    private func run(animated: Bool, entering: Bool, _ change: () -> Void, completion: (() -> Void)? = nil) {
        guard animated else {
            withoutAnimation(change)
            completion?()
            return
        }
        let duration = Motion.Duration.popover
        let animation = presentation.accessibility.animation(entering ? Motion.enter(duration) : Motion.exit(duration))
        withAnimation(animation, completionCriteria: .removed, change) {
            completion?()
        }
    }

    // MARK: Placing

    /// Under the menu bar, centred on the item and kept on its display, the top
    /// edge fixed as the content grows or shrinks.
    private func place() {
        guard let button = anchor, let itemWindow = button.window else { return }
        let item = itemWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = (itemWindow.screen ?? NSScreen.main)?.visibleFrame ?? item
        let margins = PopoverRoot<EmptyView>.margins
        let size = CGSize(
            width: presentation.size.width + margins.leading + margins.trailing,
            height: presentation.size.height + margins.top + margins.bottom
        )
        let x = min(max(item.midX - size.width / 2, screen.minX - margins.leading), screen.maxX - size.width + margins.trailing)
        // The item's window is as tall as the menu bar, so its bottom is the menu bar's.
        let frame = CGRect(x: x, y: itemWindow.frame.minY - size.height, width: size.width, height: size.height)
        if panel.frame != frame {
            panel.setFrame(frame, display: true)
        }
    }

    // MARK: Closing from outside

    private func startWatching() {
        guard monitors.isEmpty else { return }
        let clicks: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // Another app's window, the desktop, the Dock, another menu-bar item. The
        // menu bar hands a click on the item to the app from outside, so that one
        // is seen here too, and left to the item's own toggle.
        let global = NSEvent.addGlobalMonitorForEvents(matching: clicks) { [weak self] _ in
            guard let self, !isOverItem(NSEvent.mouseLocation) else { return }
            close(animated: true)
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: clicks.union(.keyDown)) { [weak self] event in
            self?.handle(event) ?? event
        }
        monitors = [global, local].compactMap(\.self)
    }

    private func stopWatching() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors = []
    }

    /// `point` is in AppKit's global coordinates.
    private func isOverItem(_ point: CGPoint) -> Bool {
        guard let button = anchor, let window = button.window else { return false }
        return window.convertToScreen(button.convert(button.bounds, to: nil)).contains(point)
    }

    /// Escape closes without motion, wherever focus is; a click in another of the
    /// app's windows, or beside the popover in its own panel, closes with it.
    private func handle(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyDown {
            guard event.keyCode == KeyCode.escape else { return event }
            close(animated: false)
            return nil
        }
        guard let window = event.window, window !== anchor?.window else { return event }
        if window === panel {
            // The panel is the popover with room for its shadow around it.
            let margins = PopoverRoot<EmptyView>.margins
            let popover = CGRect(origin: CGPoint(x: margins.leading, y: margins.bottom), size: presentation.size)
            if !popover.contains(event.locationInWindow) { close(animated: true) }
        } else if window.level == .normal {
            // Not a menu opened from inside the popover: that sits at the menu level, and its click is the popover's.
            close(animated: true)
        }
        return event
    }

    /// Another of the app's windows took over, such as the library window.
    func windowDidResignKey(_ notification: Notification) {
        close(animated: true)
    }
}

private nonisolated enum KeyCode {
    static let escape: UInt16 = 53
}

/// What the panel and its root share.
@Observable
private final class PopoverPresentation {
    var isPresented = false
    /// The popover's laid-out size.
    var size = CGSize.zero
    /// The root's accessibility settings, so a change started from AppKit runs
    /// the motion the component would. Until the root is first drawn, the launch
    /// options over System Settings, as `@Accessibility` reads them.
    var accessibility = DesignSystem.AccessibilitySettings()
    @ObservationIgnored var sizeChanged: (() -> Void)?
}

/// Draws the popover at the top of the panel, with room around it for its shadow.
private struct PopoverRoot<Content: View>: View {
    /// `GlassPopover`'s shadow falls 24 pt around it and 10 pt down; the top is
    /// the gap under the menu bar.
    static var margins: EdgeInsets {
        EdgeInsets(
            top: Spacing.tight,
            leading: Spacing.extraLarge,
            bottom: Spacing.extraLarge + Spacing.medium,
            trailing: Spacing.extraLarge
        )
    }

    @Accessibility private var accessibility
    @AccessibilityFocusState private var isFocused: Bool
    let presentation: PopoverPresentation
    let contentPadding: CGFloat
    let content: Content

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            if presentation.isPresented {
                GlassPopover(contentPadding: contentPadding) { content }
                    .fixedSize()
                    // The laid-out size, which the transition's scale leaves alone,
                    // so the panel keeps its size while the popover leaves.
                    .onGeometryChange(for: CGSize.self, of: \.size) { size in
                        presentation.size = size
                        presentation.sizeChanged?()
                    }
                    // VoiceOver goes into the popover, which is not in the app it was in.
                    .accessibilityFocused($isFocused)
                    .onAppear { isFocused = true }
                    .transition(.glassPopover(anchor: .top, reduceMotion: accessibility.reduceMotion))
            }
        }
        .padding(Self.margins)
        .onChange(of: accessibility, initial: true) { _, accessibility in
            presentation.accessibility = accessibility
        }
    }
}

/// Borderless, transparent and non-activating: the popover draws itself and its
/// shadow, clicks on the transparent room around it fall through to what is
/// underneath, and the app the user was in stays frontmost. It can be key, so
/// that Escape and the keyboard reach it.
private final class PopoverPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .popUpMenu
        collectionBehavior = [.transient, .ignoresCycle, .moveToActiveSpace, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        // SwiftUI runs the enter and the exit; AppKit's own would double them.
        animationBehavior = .none
        title = "Livepaper"
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
