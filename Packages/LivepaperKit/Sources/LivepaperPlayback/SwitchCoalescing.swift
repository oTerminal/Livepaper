import Foundation

enum SwitchEvent: Equatable, Sendable {
    /// Play this video, in place.
    case request(URL)
    /// The engine has to flush for a reason of its own: the renderer failed or asked for a
    /// flush, or a recovery asked for one.
    case flushBegan
    /// The renderer finished flushing.
    case flushEnded
}

enum SwitchAction: Equatable, Sendable {
    case none
    /// Stop reading and flush the renderer, keeping the picture on screen.
    case flush
    /// Start this video on a fresh timeline from a fresh reader.
    case start(URL)
}

/// Switching in place on one layer: the last request wins, and
/// requests that arrive while the renderer is flushing become one restart when it ends. The
/// flush is the only wait in a switch, so this is the whole of the coalescing.
struct SwitchCoalescer: Equatable, Sendable {
    /// The video the engine is feeding, or will once its flush ends.
    private(set) var playing: URL?
    /// The latest request that arrived during a flush.
    private(set) var wanted: URL?
    private(set) var isFlushing = false

    mutating func handle(_ event: SwitchEvent) -> SwitchAction {
        switch event {
        case .request(let url):
            if isFlushing {
                wanted = url
                return .none
            }
            if url == playing { return .none }
            guard playing != nil else {
                playing = url
                return .start(url)
            }
            wanted = url
            isFlushing = true
            return .flush

        case .flushBegan:
            guard !isFlushing, playing != nil else { return .none }
            isFlushing = true
            return .flush

        case .flushEnded:
            guard isFlushing else { return .none }
            isFlushing = false
            let next = wanted ?? playing
            wanted = nil
            playing = next
            return next.map(SwitchAction.start) ?? .none
        }
    }

    /// A switch while the engine may not play (suspended): nothing starts, and this is what
    /// plays when it may again.
    mutating func remember(_ url: URL) {
        playing = url
        wanted = nil
        isFlushing = false
    }
}
