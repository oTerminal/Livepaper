import Foundation
import LivepaperSoak
import Testing

struct SoakMarkerTests {
    @Test
    func `reads soak.sh's events, counting a row it cannot read`() {
        let csv = """
        time,kind,note
        2026-09-28T10:00:00+0100,start,
        2026-09-28T10:20:00+0100,lid,10 s closed
        2026-09-28T10:25:00+0100,sneeze,
        2026-09-28T11:00:00+0100,fus,
        """

        let read = SoakMarker.read(csv: csv)

        #expect(read.markers == [
            SoakMarker(time: Date(timeIntervalSince1970: 1_790_586_000), kind: .start),
            SoakMarker(time: Date(timeIntervalSince1970: 1_790_587_200), kind: .lid, note: "10 s closed"),
            SoakMarker(time: Date(timeIntervalSince1970: 1_790_589_600), kind: .fastUserSwitch),
        ])
        #expect(read.unreadRows == 1)
    }
}
