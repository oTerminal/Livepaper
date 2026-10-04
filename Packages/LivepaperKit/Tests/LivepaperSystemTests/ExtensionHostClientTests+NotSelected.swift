import Foundation
import LivepaperCore
import LivepaperSystem
import LivepaperTestSupport
import Testing

/// Not selected is not silence: before an automatic restart the client reads the
/// wallpaper store (never writing it) and the shared record of the last restart,
/// in the same turn, so the status it says is the one it ends at.
extension ExtensionHostClientTests {
    @Test func `silence with Livepaper named nowhere in the store is not selected, and restarts nothing`() async throws {
        wallpaperStore.answer = WallpaperStoreShape(store: .read(desktopEntries: 2, namingLivepaper: 0), keptCopyExists: false)
        try await client.activate()
        var statuses = client.status.makeAsyncIterator()

        clock.advance(toSecond: 3600)

        var seen: [RenderHostStatus] = []
        while let status = await statuses.next() {
            seen.append(status)
            if status == .notSelected { break }
        }
        #expect(seen == [.connecting, .recovering(.flush), .notSelected], "never a restart the popover would offer")
        #expect(agent.restarts == 0)
        #expect(restarts.lastRestart == nil)
        #expect(wallpaperStore.reads == 1)
        #expect(clock.scheduled.isEmpty)
    }

    @Test func `a restart Selection recorded after activation holds the ladder's restart back ten minutes`() async throws {
        try await client.activate()
        clock.advance(toSecond: 10)
        // Selection writes the shared record before its killall.
        restarts.lastRestart = clock.now

        clock.advance(toSecond: 3600)

        var asked = agent.asked.makeAsyncIterator()
        #expect(await asked.next() == 1)
        #expect(agent.restarts == 1)
        #expect(client.lastAgentRestart.map(Moment.millisecond(of:)) == 610_001)
        #expect(restarts.lastRestart.map(Moment.millisecond(of:)) == 610_001)
    }
}
