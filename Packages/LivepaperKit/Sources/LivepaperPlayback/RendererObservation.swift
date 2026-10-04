import AVFoundation

/// What the video renderer says of itself without being asked. A renderer that failed, or that
/// needs a flush before it decodes again, stops asking for data, so the pull callback that
/// would notice it may never come.
enum RendererSignal: Sendable {
    case failedToDecode((any Error)?)
    /// `requiresFlushToResumeDecoding` changed, to true or back to false.
    case requiresFlushChanged
}

/// Hears one renderer's signals for as long as it lives. The handler is called on whichever
/// thread AVFoundation posts from, possibly inside a call on the renderer, so it only hands
/// the signal on.
final class RendererObservation {
    private let tokens: [any NSObjectProtocol]

    init(_ renderer: AVSampleBufferVideoRenderer, _ handler: @escaping @Sendable (RendererSignal) -> Void) {
        let centre = NotificationCenter.default
        tokens = [
            centre.addObserver(
                forName: AVSampleBufferVideoRenderer.didFailToDecodeNotification,
                object: renderer,
                queue: nil
            ) { notification in
                let error = notification.userInfo?[AVSampleBufferVideoRenderer.didFailToDecodeNotificationErrorKey] as? NSError
                handler(.failedToDecode(error))
            },
            centre.addObserver(
                forName: AVSampleBufferVideoRenderer.requiresFlushToResumeDecodingDidChangeNotification,
                object: renderer,
                queue: nil
            ) { _ in
                handler(.requiresFlushChanged)
            },
        ]
    }

    deinit {
        for token in tokens { NotificationCenter.default.removeObserver(token) }
    }
}
