import Foundation
import Synchronization

/// Whether the task that started some blocking work has been cancelled since.
final class Cancellation: Sendable {
    private let cancelled = Atomic(false)

    var isCancelled: Bool { cancelled.load(ordering: .relaxed) }

    func cancel() {
        cancelled.store(true, ordering: .relaxed)
    }

    func check() throws {
        if isCancelled { throw CancellationError() }
    }
}

/// Runs work that blocks on a thread of its own.
///
/// `AVAssetReaderOutput.copyNextSampleBuffer()` waits for the next sample, and
/// a writer input is waited for until it is ready. On Swift's cooperative pool,
/// which has one thread per core, a batch of imports doing that at once takes
/// every thread, and the reader, which needs one to make progress, never
/// returns. So nothing in this module blocks on that pool.
func onOwnThread<Value: Sendable>(_ work: @escaping @Sendable (Cancellation) throws -> Value) async throws -> Value {
    let cancellation = Cancellation()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            Thread.detachNewThread {
                continuation.resume(with: Result { try work(cancellation) })
            }
        }
    } onCancel: {
        cancellation.cancel()
    }
}

/// Carries a value AVFoundation has not marked Sendable to the thread that
/// will use it. For assets and tracks, which are immutable and which
/// AVFoundation documents as safe to read from any thread, and for readers and
/// writers that are handed over whole and not touched again by the sender.
struct Unchecked<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
