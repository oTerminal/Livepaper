import Foundation
import LivepaperCore
import Testing

struct CommandOutcomeTests {
    static let first = DisplayIdentity.numbered(1)
    static let second = DisplayIdentity.numbered(2)
    static let unplugged = DisplayIdentity.numbered(3)
    static let evening = Playlist(
        id: .numbered(1), name: "Evening", wallpapers: [.numbered(1), .numbered(2)], interval: .seconds(600), shuffle: false
    )

    // MARK: The displays a command names

    static let targets: [Row<DisplayTarget, Result<[DisplayIdentity], CommandRefusal>>] = [
        Row("all is every connected display, in their order", .all, .success([first, second])),
        Row("a connected display is itself", .display(second), .success([second])),
        Row("a display that is not connected is refused", .display(unplugged), .failure(.notConnected(unplugged))),
    ]

    @Test(arguments: targets)
    func `a command acts on connected displays only`(row: Row<DisplayTarget, Result<[DisplayIdentity], CommandRefusal>>) {
        #expect(Result { () throws(CommandRefusal) in try row.input.displays(connected: [Self.first, Self.second]) } == row.expected)
    }

    // MARK: What set names

    static let assignments: [Row<Assignment, CommandRefusal?>] = [
        Row("a wallpaper the library holds", .wallpaper(.numbered(1)), nil),
        Row("a wallpaper the library does not hold is refused", .wallpaper(.numbered(9)), .noSuchWallpaper(.numbered(9))),
        Row("a playlist there is", .playlist(evening.id), nil),
        Row("a playlist there is not is refused", .playlist(.numbered(9)), .noSuchPlaylist(.numbered(9))),
    ]

    @Test(arguments: assignments)
    func `set names only what the library holds`(row: Row<Assignment, CommandRefusal?>) throws {
        var state = AppState()
        state.playlists = [Self.evening]
        let library = try Library.of(.numbered(1), .numbered(2))

        let refusal: CommandRefusal?
        do throws(CommandRefusal) {
            try state.checking(row.input, in: library)
            refusal = nil
        } catch {
            refusal = error
        }

        #expect(refusal == row.expected)
    }

    // MARK: What next moves on

    struct Showing: Sendable {
        var own: [DisplayIdentity: Assignment] = [:]
        var applyToAll: Assignment?
        var target: DisplayTarget
    }

    static let movingOn: [Row<Showing, Result<[DisplayIdentity], CommandRefusal>>] = [
        Row(
            "all moves on each display showing a playlist, and leaves the rest",
            Showing(own: [second: .playlist(evening.id), first: .wallpaper(.numbered(1))], target: .all),
            .success([second])
        ),
        Row(
            "a playlist on All Displays moves every display on",
            Showing(applyToAll: .playlist(evening.id), target: .all),
            .success([first, second])
        ),
        Row(
            "all with no playlist showing is refused",
            Showing(own: [first: .wallpaper(.numbered(1))], target: .all),
            .failure(.noPlaylistShown(.all))
        ),
        Row("one display on a playlist", Showing(own: [first: .playlist(evening.id)], target: .display(first)), .success([first])),
        Row(
            "one display showing a wallpaper is refused",
            Showing(own: [first: .wallpaper(.numbered(1)), second: .playlist(evening.id)], target: .display(first)),
            .failure(.noPlaylistShown(.display(first)))
        ),
        Row(
            "a display that is not connected is refused",
            Showing(own: [unplugged: .playlist(evening.id)], target: .display(unplugged)),
            .failure(.notConnected(unplugged))
        ),
        Row(
            "a playlist that is gone moves nothing",
            Showing(own: [first: .playlist(.numbered(9))], target: .all),
            .failure(.noPlaylistShown(.all))
        ),
    ]

    @Test(arguments: movingOn)
    func `next moves on the displays that show a playlist`(row: Row<Showing, Result<[DisplayIdentity], CommandRefusal>>) {
        var state = AppState()
        state.playlists = [Self.evening]
        state.assignments = row.input.own
        state.applyToAll = row.input.applyToAll

        let connected = [Self.first, Self.second]

        let moving = Result { () throws(CommandRefusal) in try state.displaysMovingOn(row.input.target, connected: connected) }

        #expect(moving == row.expected)
    }

    static let reasons: [Row<CommandRefusal, String>] = [
        Row("a wallpaper", .noSuchWallpaper(.numbered(9)), "The library has no wallpaper AAAAAAAA-0000-0000-0000-000000000009"),
        Row("a playlist", .noSuchPlaylist(.numbered(9)), "There is no playlist BBBBBBBB-0000-0000-0000-000000000009"),
        Row("a display", .notConnected(unplugged), "Display DDDDDDDD-0000-0000-0000-000000000003 is not connected"),
        Row("no playlist anywhere", .noPlaylistShown(.all), "No display shows a playlist"),
        Row(
            "no playlist there",
            .noPlaylistShown(.display(first)),
            "Display DDDDDDDD-0000-0000-0000-000000000001 does not show a playlist"
        ),
        Row("an unreadable library", .libraryUnreadable, "The library could not be read, so Livepaper changes nothing"),
        Row("quitting", .quitting, "Livepaper is quitting"),
        Row("still starting, after the wait", .stillStarting, "Livepaper is still starting; try again in a moment"),
    ]

    @Test(arguments: reasons)
    func `a refusal says why in a sentence`(row: Row<CommandRefusal, String>) {
        #expect(row.input.reason == row.expected)
        #expect(CommandReply.refused(row.input) == .refused(reason: row.expected))
    }

    // MARK: Next's reply

    @Test func `next answers what each display it moved on shows now`() {
        let reply = CommandReply.movedOn([("Built-in Retina Display", "Northern Lights"), ("Studio Display", nil)])

        #expect(reply == .done(message: "Built-in Retina Display now shows “Northern Lights”.\nStudio Display moved on."))
    }
}
