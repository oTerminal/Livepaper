import Dispatch
import Synchronization
import Testing
@testable import LivepaperPlayback

struct RetirementGateTests {
    @Test func `a call goes through while the gate is open`() {
        let gate = RetirementGate(7)

        let seen = gate.pass { $0 }

        #expect(seen == 7)
        #expect(!gate.isClosed)
    }

    @Test func `no call goes through once the gate has closed`() {
        let gate = RetirementGate(7)
        let calls = Lines()

        gate.close()
        let seen = gate.pass { value in
            calls.add("call")
            return value
        }

        #expect(seen == nil)
        #expect(calls.all.isEmpty)
        #expect(gate.isClosed)
    }

    @Test func `the last call at closing sees what the calls before it left, and runs once`() {
        let gate = RetirementGate(0)
        let lines = Lines()

        gate.pass { $0 += 1 }
        gate.close { lines.add("closing on \($0)") }
        gate.close { lines.add("closing again on \($0)") }

        #expect(lines.all == ["closing on 1"])
    }

    /// The read that blocked an engine's queue returns after the engine was retired: the call
    /// under way finishes before closing does, and nothing comes after it.
    @Test func `closing waits for a call under way`() async {
        let gate = RetirementGate(0)
        let lines = Lines()
        let entered = DispatchSemaphore(value: 0)
        let release = DispatchSemaphore(value: 0)

        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                gate.pass { _ in
                    lines.add("call began")
                    entered.signal()
                    release.wait()
                    lines.add("call ended")
                }
            }
            DispatchQueue.global().async {
                entered.wait()
                DispatchQueue.global().async { release.signal() }
                gate.close { _ in lines.add("closed") }
                gate.pass { _ in lines.add("call after closing") }
                done.resume()
            }
        }

        #expect(lines.all == ["call began", "call ended", "closed"])
    }
}

/// Lines written from any thread, in the order they came.
private final class Lines: Sendable {
    private let lines = Mutex<[String]>([])

    func add(_ line: String) {
        lines.withLock { $0.append(line) }
    }

    var all: [String] {
        lines.withLock { $0 }
    }
}
