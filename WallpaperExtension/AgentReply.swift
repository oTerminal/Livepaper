import Foundation

/// Answers one of WallpaperAgent's calls exactly once: with what the work
/// gives when it is done, or, if it takes longer than `limit`, with what
/// `late` gives then. The agent waits on the answer, so it must never hang
/// (an acquire is answered within 2 s).
final class AgentReply<Value> {
    private var reply: ((Value) -> Void)?
    private var deadline: Task<Void, Never>?

    init(within limit: Duration, reply: @escaping @Sendable (Value) -> Void, late: @escaping () -> Value) {
        self.reply = reply
        // Holds the reply until it fires or is cancelled, so that the answer
        // goes out even if nothing else is left waiting for the work.
        deadline = Task {
            do { try await Task.sleep(for: limit) } catch { return }
            guard self.reply != nil else { return }
            self.send(late())
        }
    }

    /// Answers, unless the agent has been answered already.
    func send(_ value: Value) {
        guard let reply else { return }
        self.reply = nil
        deadline?.cancel()
        deadline = nil
        reply(value)
    }
}
