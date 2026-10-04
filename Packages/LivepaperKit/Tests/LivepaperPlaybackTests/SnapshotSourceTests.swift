import Testing
@testable import LivepaperPlayback

struct SnapshotSourceTests {
    struct Surface: Sendable {
        var state: SurfacePlaybackState
        var hasWallpaper = true
        var front: VideoSlot?
    }

    static let rows: [Row<Surface, [SnapshotSource]>] = [
        Row("with no wallpaper there is nothing to hand back", Surface(state: .nothing, hasWallpaper: false), []),
        Row("holding the still, the poster", Surface(state: .still), [.poster, .neutralColour]),
        Row(
            "a video playing, its picture, and the poster while its layer has none",
            Surface(state: .playing, front: .lower),
            [.video(.lower), .poster, .neutralColour]
        ),
        Row(
            "a video on the upper layer, that layer's picture",
            Surface(state: .playing, front: .upper),
            [.video(.upper), .poster, .neutralColour]
        ),
        Row("a video paused, its picture", Surface(state: .paused, front: .lower), [.video(.lower), .poster, .neutralColour]),
        Row(
            "a video suspended, the picture it kept",
            Surface(state: .suspended, front: .lower),
            [.video(.lower), .poster, .neutralColour]
        ),
        Row("the first video still starting, just after acquire, the poster", Surface(state: .playing), [.poster, .neutralColour]),
        Row("the still being read, the poster", Surface(state: .nothing), [.poster, .neutralColour]),
    ]

    @Test(arguments: rows)
    func `hands back what the surface shows, the poster standing in for a video without a picture`(
        row: Row<Surface, [SnapshotSource]>
    ) {
        let surface = row.input

        let sources = snapshotSources(state: surface.state, hasWallpaper: surface.hasWallpaper, front: surface.front)

        #expect(sources == row.expected)
    }
}
