import Foundation
import LivepaperCore
import LivepaperTestSupport
import Synchronization
import Testing

/// A command waits for the launch to be ready, for a while at most: the
/// `livepaper` tool waits on its reply with no limit of its own, so a launch
/// that never becomes ready must be answered, not waited on for ever.
@Suite(.timeLimit(.minutes(1)))
struct PollingTests {
    final class Flag: Sendable {
        private let value = Mutex(false)

        var isUp: Bool { value.withLock { $0 } }

        func raise() {
            value.withLock { $0 = true }
        }
    }

    let clock = ManualClock(start: Moment.launch)
    let flag = Flag()

    func waiting(within limit: Duration?) -> Task<Bool, Never> {
        Task { [clock, flag] in
            await Polling.wait(until: { flag.isUp }, every: .milliseconds(20), within: limit, clock: clock)
        }
    }

    /// Until the waiting task sleeps between two looks.
    func untilSleeping() async {
        while clock.sleeperCount == 0 {
            await Task.yield()
        }
    }

    @Test func `a condition that holds already is answered at once`() async {
        flag.raise()

        #expect(await waiting(within: .seconds(10)).value)
        #expect(clock.sleeperCount == 0)
    }

    @Test func `a condition that comes true is seen at the next look`() async {
        let wait = waiting(within: .seconds(10))
        await untilSleeping()

        flag.raise()
        clock.advance(by: .milliseconds(20))

        #expect(await wait.value)
    }

    @Test func `a condition that never holds is given up at the limit`() async {
        let wait = waiting(within: .seconds(10))
        await untilSleeping()

        clock.advance(by: .seconds(10))

        #expect(await wait.value == false)
    }

    @Test func `without a limit, it waits for as long as it takes`() async {
        let wait = waiting(within: nil)
        await untilSleeping()
        clock.advance(by: .seconds(3600))
        await untilSleeping()

        flag.raise()
        clock.advance(by: .milliseconds(20))

        #expect(await wait.value)
    }

    @Test func `a cancelled wait answers that it did not hold`() async {
        let wait = waiting(within: nil)
        await untilSleeping()

        wait.cancel()

        #expect(await wait.value == false)
    }
}
