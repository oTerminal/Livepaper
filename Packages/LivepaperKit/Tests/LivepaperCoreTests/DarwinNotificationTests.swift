import Foundation
import Testing
import LivepaperCore

struct DarwinNotificationTests {
    @Test func `an observer is woken with the state that was posted`() async {
        let notification = DarwinNotification("app.livepaper.tests.\(UUID().uuidString)")
        let (states, continuation) = AsyncStream.makeStream(of: UInt64.self)
        let observation = notification.observe(on: DispatchQueue(label: "DarwinNotificationTests")) { state in
            continuation.yield(state)
        }
        #expect(observation != nil)

        notification.post(state: 0x0000_0010_0000_0007)
        var iterator = states.makeAsyncIterator()

        #expect(await iterator.next() == 0x0000_0010_0000_0007)
        #expect(notification.currentState() == 0x0000_0010_0000_0007)
        observation?.cancel()
    }
}
