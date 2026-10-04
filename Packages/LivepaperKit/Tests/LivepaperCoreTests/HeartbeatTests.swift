import Foundation
import Testing
import LivepaperCore

struct HeartbeatTests {
    static let everyFlag: [Row<Heartbeat.Flags, UInt64>] = [
        Row("no flags", [], 0x0000_0000_0000_0007),
        Row("a desktop surface is acquired: the user has selected Livepaper", .desktopSurfaceAcquired, 0x0000_0001_0000_0007),
        Row("holding a still", .holdingStill, 0x0000_0002_0000_0007),
        Row("a reconnect spiral, asking for an agent restart", .spiralDetected, 0x0000_0004_0000_0007),
        Row("the launch self-check failed", .selfCheckFailed, 0x0000_0008_0000_0007),
        Row("the watchdog reached the top of its ladder, asking for an agent restart", .restartAgentRequested, 0x0000_0010_0000_0007),
        Row("several at once", [.desktopSurfaceAcquired, .holdingStill, .selfCheckFailed], 0x0000_000B_0000_0007),
        Row("a flag from a newer extension survives", Heartbeat.Flags(rawValue: 0x8000_0000), 0x8000_0000_0000_0007),
    ]

    @Test(arguments: everyFlag)
    func `packs generation 7 with each flag, and unpacks it again`(row: Row<Heartbeat.Flags, UInt64>) {
        let heartbeat = Heartbeat(generation: 7, flags: row.input)

        #expect(heartbeat.packed == row.expected)
        #expect(Heartbeat(packed: row.expected) == heartbeat)
    }

    @Test func `every flag has its own bit`() {
        let all: [Heartbeat.Flags] = [.desktopSurfaceAcquired, .holdingStill, .spiralDetected, .selfCheckFailed, .restartAgentRequested]

        #expect(Set(all.map(\.rawValue)).count == all.count)
        #expect(all.allSatisfy { $0.rawValue.nonzeroBitCount == 1 })
    }

    static let generations: [Row<UInt64, UInt32>] = [
        Row("a small generation is carried whole", 7, 7),
        Row("the largest 32-bit generation is carried whole", 0xFFFF_FFFF, 0xFFFF_FFFF),
        Row("the next one wraps to zero", 0x1_0000_0000, 0),
        Row("and counting carries on from there", 0x1_0000_0005, 5),
    ]

    @Test(arguments: generations)
    func `the generation wraps safely`(row: Row<UInt64, UInt32>) {
        let heartbeat = Heartbeat(acknowledging: row.input, flags: .desktopSurfaceAcquired)

        #expect(heartbeat.generation == row.expected)
        #expect(Heartbeat(packed: heartbeat.packed) == heartbeat)
        #expect(heartbeat.flags == .desktopSurfaceAcquired, "the generation never spills into the flags")
        #expect(heartbeat.acknowledges(row.input))
        #expect(!heartbeat.acknowledges(row.input + 1))
    }

    @Test func `a state that was never set is a heartbeat with nothing to report`() {
        #expect(Heartbeat(packed: 0) == Heartbeat(generation: 0, flags: []))
    }
}
