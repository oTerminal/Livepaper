import Testing
@testable import LivepaperPlayback

struct CrossfadePlanTests {
    struct Request: Sendable {
        var front: VideoSlot?
        var incoming: VideoSlot?
        var crossfade: Bool
    }

    static let rows: [Row<Request, CrossfadePlan>] = [
        Row(
            "with nothing showing the lower layer is cleared and starts, opaque once it has a picture, without a fade",
            Request(front: nil, incoming: nil, crossfade: true),
            CrossfadePlan(
                start: .fresh(.lower),
                clears: .lower,
                before: [OpacityChange(.upper, 0)],
                whenReady: [OpacityChange(.lower, 1)]
            )
        ),
        Row(
            "with nothing showing and no crossfade asked the same",
            Request(front: nil, incoming: nil, crossfade: false),
            CrossfadePlan(
                start: .fresh(.lower),
                clears: .lower,
                before: [OpacityChange(.upper, 0)],
                whenReady: [OpacityChange(.lower, 1)]
            )
        ),
        Row(
            "a request while the first engine is still starting redirects it",
            Request(front: nil, incoming: .lower, crossfade: true),
            CrossfadePlan(start: .redirect(.lower))
        ),
        Row(
            "a new video over the lower layer fades in on the upper one, cleared first",
            Request(front: .lower, incoming: nil, crossfade: true),
            CrossfadePlan(
                start: .fresh(.upper),
                clears: .upper,
                before: [OpacityChange(.upper, 0)],
                fade: OpacityChange(.upper, 1),
                stops: .lower
            )
        ),
        Row(
            "a new video under the upper layer starts there, cleared first, and the upper one fades out",
            Request(front: .upper, incoming: nil, crossfade: true),
            CrossfadePlan(
                start: .fresh(.lower),
                clears: .lower,
                before: [OpacityChange(.lower, 1)],
                fade: OpacityChange(.upper, 0),
                stops: .upper
            )
        ),
        Row(
            "without a crossfade the lower layer switches in place",
            Request(front: .lower, incoming: nil, crossfade: false),
            CrossfadePlan(start: .inPlace(.lower))
        ),
        Row(
            "without a crossfade the upper layer switches in place",
            Request(front: .upper, incoming: nil, crossfade: false),
            CrossfadePlan(start: .inPlace(.upper))
        ),
        Row(
            "a request during a crossfade waits for it to end",
            Request(front: .lower, incoming: .upper, crossfade: true),
            CrossfadePlan(start: .afterCrossfade)
        ),
        Row(
            "a request during a crossfade back waits for it too, crossfade or not",
            Request(front: .upper, incoming: .lower, crossfade: false),
            CrossfadePlan(start: .afterCrossfade)
        ),
    ]

    @Test(arguments: rows)
    func `plans the change of video`(row: Row<Request, CrossfadePlan>) {
        let situation = CrossfadeSituation(front: row.input.front, incoming: row.input.incoming)

        let plan = planCrossfade(situation, crossfade: row.input.crossfade)

        #expect(plan == row.expected)
    }

    /// The two layers at rest with a video showing, as a crossfade finds them: the one in front
    /// has its picture; the other may still hold a picture from before, since a rebuild retires
    /// its engine without touching the layer.
    struct AtRest: Sendable {
        var front: VideoSlot
        var otherHoldsOldPicture: Bool
    }

    static let atRest: [Row<AtRest, Void>] = [
        Row("from the lower layer", AtRest(front: .lower, otherHoldsOldPicture: false), ()),
        Row("from the upper layer", AtRest(front: .upper, otherHoldsOldPicture: false), ()),
        Row("from the lower layer, the upper one holding an old picture", AtRest(front: .lower, otherHoldsOldPicture: true), ()),
        Row("from the upper layer, the lower one holding an old picture", AtRest(front: .upper, otherHoldsOldPicture: true), ()),
    ]

    @Test(arguments: atRest)
    func `a crossfade always has a fully visible video, and starts on the new one`(row: Row<AtRest, Void>) throws {
        let front = row.input.front
        var layers = LayerModel(front: front, otherHoldsOldPicture: row.input.otherHoldsOldPicture)
        let plan = planCrossfade(CrossfadeSituation(front: front, incoming: nil), crossfade: true)
        guard case .fresh(let starting) = plan.start else {
            Issue.record("a crossfade starts a fresh engine: \(plan)")
            return
        }
        let fade = try #require(plan.fade)

        layers.apply(plan.before)
        if let clears = plan.clears { layers.clear(clears) }
        #expect(layers.showsVideo, "while the new engine starts")
        #expect(!layers.isReadyForDisplay(starting), "before the new video is on the starting layer")

        layers.show(.new, on: starting)
        layers.apply(plan.whenReady)
        #expect(layers.showsVideo, "once the new video is ready")

        layers.apply([OpacityChange(fade.slot, (layers[fade.slot].opacity + fade.opacity) / 2)])
        #expect(layers.showsVideo, "halfway through the fade")

        layers.apply([fade])
        #expect(layers.showsVideo, "at the end of the fade")

        if let stops = plan.stops { layers.clear(stops) }
        #expect(layers.showsVideo, "once the old engine stopped")
        #expect(layers[starting].opacity == 1)
        #expect(layers[starting].picture == .new)
    }

    static let fromNothing: [Row<Bool, Void>] = [
        Row("on layers that were cleared", false, ()),
        Row("on a lower layer still holding an old picture", true, ()),
    ]

    @Test(arguments: fromNothing)
    func `from nothing the lower layer shows only once it has the new video`(row: Row<Bool, Void>) {
        var layers = LayerModel(front: nil, otherHoldsOldPicture: row.input)
        let plan = planCrossfade(CrossfadeSituation(front: nil, incoming: nil), crossfade: false)

        layers.apply(plan.before)
        if let clears = plan.clears { layers.clear(clears) }
        #expect(!layers.isReadyForDisplay(.lower), "before the new video is on the layer")

        layers.show(.new, on: .lower)
        layers.apply(plan.whenReady)
        #expect(layers[.lower].opacity == 1)
        #expect(layers[.lower].picture == .new)
    }
}

/// What the spike's poll looked at: whether some video layer is fully opaque and has a picture, and
/// which picture that is.
private struct LayerModel {
    enum Picture {
        case old
        case new
    }

    struct Layer {
        var opacity: Float
        var picture: Picture?
    }

    private var layers: [VideoSlot: Layer]

    /// With a front, the layer in front shows its video and the other one is at rest (the lower
    /// one is opaque once it has played); with none, both are clear and hidden. The other layer,
    /// or the lower one when nothing shows, may still hold a picture from before.
    init(front: VideoSlot?, otherHoldsOldPicture: Bool) {
        let leftover: Picture? = otherHoldsOldPicture ? .old : nil
        layers = switch front {
        case .lower: [.lower: Layer(opacity: 1, picture: .old), .upper: Layer(opacity: 0, picture: leftover)]
        case .upper: [.lower: Layer(opacity: 1, picture: leftover), .upper: Layer(opacity: 1, picture: .old)]
        case nil: [.lower: Layer(opacity: 0, picture: leftover), .upper: Layer(opacity: 0, picture: nil)]
        }
    }

    subscript(slot: VideoSlot) -> Layer { layers[slot] ?? Layer(opacity: 0, picture: nil) }

    var showsVideo: Bool { layers.values.contains { $0.opacity >= 1 && $0.picture != nil } }

    /// What `isReadyForDisplay` reports: that the layer has a picture, whichever it is.
    func isReadyForDisplay(_ slot: VideoSlot) -> Bool { self[slot].picture != nil }

    mutating func apply(_ changes: [OpacityChange]) {
        for change in changes { layers[change.slot]?.opacity = change.opacity }
    }

    /// A flush that removes the displayed image, as `LoopEngine.stop()` does.
    mutating func clear(_ slot: VideoSlot) { layers[slot]?.picture = nil }
    mutating func show(_ picture: Picture, on slot: VideoSlot) { layers[slot]?.picture = picture }
}
