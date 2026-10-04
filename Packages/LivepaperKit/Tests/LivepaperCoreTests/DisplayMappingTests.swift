import Foundation
import Testing
import LivepaperCore

struct DisplayMappingTests {
    static let builtIn = DisplayIdentity.numbered(1)
    static let studio = DisplayIdentity.numbered(2)
    /// The same model as `studio`, bought the same day: a different identity all the same.
    static let secondStudio = DisplayIdentity.numbered(3)

    static let ocean = Assignment.wallpaper(.numbered(1))
    static let forest = Assignment.wallpaper(.numbered(2))
    static let evening = Assignment.playlist(.numbered(1))

    struct Setup: Sendable {
        var saved: [DisplayIdentity: Assignment]
        var connected: [DisplayIdentity]
        var applyToAll: Assignment?
    }

    static let rows: [Row<Setup, [DisplayIdentity: Assignment]>] = [
        Row(
            "a connected display shows its saved assignment",
            Setup(saved: [builtIn: ocean], connected: [builtIn]),
            [builtIn: ocean]
        ),
        Row(
            "an absent display is left out of what is shown",
            Setup(saved: [builtIn: ocean, studio: forest], connected: [builtIn]),
            [builtIn: ocean]
        ),
        Row(
            "a display that comes back shows what it had",
            Setup(saved: [builtIn: ocean, studio: forest], connected: [builtIn, studio]),
            [builtIn: ocean, studio: forest]
        ),
        Row(
            "a new display takes apply to all",
            Setup(saved: [builtIn: ocean], connected: [builtIn, studio], applyToAll: evening),
            [builtIn: ocean, studio: evening]
        ),
        Row(
            "a new display shows nothing without apply to all",
            Setup(saved: [builtIn: ocean], connected: [builtIn, studio]),
            [builtIn: ocean]
        ),
        Row(
            "a saved assignment beats apply to all",
            Setup(saved: [studio: forest], connected: [studio], applyToAll: evening),
            [studio: forest]
        ),
        Row(
            "two identical displays are two identities",
            Setup(saved: [studio: ocean, secondStudio: forest], connected: [studio, secondStudio]),
            [studio: ocean, secondStudio: forest]
        ),
        Row(
            "one of two identical displays can be new",
            Setup(saved: [studio: ocean], connected: [studio, secondStudio], applyToAll: evening),
            [studio: ocean, secondStudio: evening]
        ),
        Row("no displays, nothing shown", Setup(saved: [builtIn: ocean], connected: [], applyToAll: evening), [:]),
        Row(
            "a display reported twice is one display",
            Setup(saved: [builtIn: ocean], connected: [builtIn, builtIn]),
            [builtIn: ocean]
        ),
    ]

    @Test(arguments: rows)
    func `resolves assignments for the connected displays`(row: Row<Setup, [DisplayIdentity: Assignment]>) {
        let shown = resolveAssignments(row.input.saved, connected: row.input.connected, applyToAll: row.input.applyToAll)

        #expect(shown == row.expected)
    }
}
