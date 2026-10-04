/// Hands each value to every stream made from it. An `AsyncStream` has one
/// reader, so a sensor makes one stream per reader through this.
///
/// A sensor starts watching the system when its first stream is made and
/// stops when the last one ends, so that nothing is observed that nobody reads.
public final class Broadcast<Value: Sendable> {
    /// The last value sent. A new stream starts with it, when `replaysLatest` is set.
    public private(set) var latest: Value?
    private let replaysLatest: Bool
    private let bufferingPolicy: AsyncStream<Value>.Continuation.BufferingPolicy
    private var readers: [Int: AsyncStream<Value>.Continuation] = [:]
    private var nextReader = 0
    private var sends = 0
    private var onFirstReader: () -> Void = {}
    private var onLastReaderGone: () -> Void = {}

    /// A state (the displays, the power source) replays the latest value and
    /// keeps only the newest unread one; an event stream (sleep and wake) does neither.
    public init(replaysLatest: Bool = true, bufferingPolicy: AsyncStream<Value>.Continuation.BufferingPolicy = .bufferingNewest(1)) {
        self.replaysLatest = replaysLatest
        self.bufferingPolicy = bufferingPolicy
    }

    /// What to do when the first stream is made, and when the last one ends.
    /// `start` usually sends the current value.
    public func whenRead(start: @escaping () -> Void, stop: @escaping () -> Void) {
        onFirstReader = start
        onLastReaderGone = stop
    }

    public var readerCount: Int { readers.count }

    public func stream() -> AsyncStream<Value> {
        let (stream, continuation) = AsyncStream.makeStream(of: Value.self, bufferingPolicy: bufferingPolicy)
        let reader = nextReader
        nextReader += 1
        readers[reader] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.remove(reader) }
        }
        if readers.count == 1 {
            let sendsBefore = sends
            onFirstReader()
            // Starting sent the current value to every reader, this one included.
            if sends != sendsBefore { return stream }
        }
        if replaysLatest, let latest { continuation.yield(latest) }
        return stream
    }

    public func send(_ value: Value) {
        latest = value
        sends += 1
        for continuation in readers.values {
            continuation.yield(value)
        }
    }

    private func remove(_ reader: Int) {
        guard readers.removeValue(forKey: reader) != nil else { return }
        if readers.isEmpty { onLastReaderGone() }
    }
}

extension Broadcast where Value: Equatable {
    /// Reads the value again once the system has settled: after each of
    /// `waits`, counted from now, and sends it when it changed. A sensor calls
    /// this on each event and cancels the task the last event started, so a
    /// burst of events is read once, after the last of them.
    func sendSettled(after waits: [Duration], _ read: @escaping () -> Value) -> Task<Void, Never> {
        Task { [weak self] in
            var waited = Duration.zero
            for wait in waits {
                do { try await Task.sleep(for: wait - waited) } catch { return }
                waited = wait
                guard let self else { return }
                let value = read()
                if value != latest { send(value) }
            }
        }
    }
}
