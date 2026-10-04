import SwiftUI

/// Shares one `HoverDwell` between every tile in a grid, so only one tile is
/// ever live. Put it in the environment with `livePreviewScope()`.
@Observable
public final class LivePreviewCoordinator {
    /// The tile whose live preview is showing.
    public private(set) var live: AnyHashable?

    private var dwell = HoverDwell<AnyHashable, ContinuousClock.Instant>()
    private let clock = ContinuousClock()
    private var timer: Task<Void, Never>?

    public init() {}

    /// Off under Reduce Motion: posters stay posters.
    public var isEnabled: Bool {
        get { dwell.isEnabled }
        set {
            dwell.isEnabled = newValue
            publish()
        }
    }

    public func pointerEntered(_ id: AnyHashable) {
        dwell.send(.enter(id), at: clock.now)
        publish()
    }

    public func pointerExited(_ id: AnyHashable) {
        dwell.send(.exit(id), at: clock.now)
        publish()
    }

    private func publish() {
        if live != dwell.live {
            live = dwell.live
        }
        timer?.cancel()
        guard let deadline = dwell.deadline else { return }
        timer = Task { [weak self, clock] in
            try? await clock.sleep(until: deadline)
            guard let self, !Task.isCancelled else { return }
            dwell.send(.tick, at: clock.now)
            publish()
        }
    }
}

extension View {
    /// Makes the wallpaper tiles inside share one live preview between them.
    public func livePreviewScope() -> some View {
        modifier(LivePreviewScope())
    }
}

private struct LivePreviewScope: ViewModifier {
    @Accessibility private var accessibility
    @State private var coordinator = LivePreviewCoordinator()

    func body(content: Content) -> some View {
        content
            .environment(coordinator)
            .onChange(of: accessibility.reduceMotion, initial: true) { _, reduceMotion in
                coordinator.isEnabled = !reduceMotion
            }
    }
}
