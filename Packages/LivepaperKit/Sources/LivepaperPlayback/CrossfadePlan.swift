/// One of a surface's two video layers, both made up front. The upper one sits above the lower.
enum VideoSlot: Hashable, CaseIterable, Sendable {
    case lower
    case upper
}

/// One value per video layer.
struct VideoSlots<Value> {
    var lower: Value
    var upper: Value

    subscript(slot: VideoSlot) -> Value {
        get {
            switch slot {
            case .lower: lower
            case .upper: upper
            }
        }
        set {
            switch slot {
            case .lower: lower = newValue
            case .upper: upper = newValue
            }
        }
    }

    var all: [Value] { [lower, upper] }
}

extension VideoSlots: Sendable where Value: Sendable {}

/// What the two video layers are doing when another video is asked for.
struct CrossfadeSituation: Equatable, Sendable {
    /// The layer the video on screen is on, nil while no video shows.
    var front: VideoSlot?
    /// A layer whose engine is starting or fading in, nil while the layers are at rest.
    var incoming: VideoSlot?
}

struct OpacityChange: Equatable, Sendable {
    var slot: VideoSlot
    var opacity: Float

    init(_ slot: VideoSlot, _ opacity: Float) {
        self.slot = slot
        self.opacity = opacity
    }
}

/// How a surface moves to another video. The lower layer is opaque
/// once it has played and only the upper layer's opacity is ever animated, so in either
/// direction something opaque with a picture is always there. A fresh start waits for its
/// layer to be ready for display, so the layer is cleared of any earlier picture first: its
/// readiness is then the new video's first picture.
struct CrossfadePlan: Equatable, Sendable {
    enum Start: Equatable, Sendable {
        /// The engine on this layer starts the new video on a fresh timeline.
        case fresh(VideoSlot)
        /// The engine still starting on this layer is sent to the new video instead.
        case redirect(VideoSlot)
        /// The engine on this layer switches to the new video in place.
        case inPlace(VideoSlot)
        /// A crossfade is under way: the request waits for it to end, and the last one wins.
        case afterCrossfade
    }

    var start: Start
    /// The layer whose picture is taken off before its engine starts.
    var clears: VideoSlot?
    /// Set at once, before the engine starts.
    var before: [OpacityChange] = []
    /// Set at once when the starting layer reports it is ready for display.
    var whenReady: [OpacityChange] = []
    /// The one animated change, started when the starting layer is ready for display.
    var fade: OpacityChange?
    /// The layer whose engine stops once the fade is over.
    var stops: VideoSlot?
}

func planCrossfade(_ situation: CrossfadeSituation, crossfade: Bool) -> CrossfadePlan {
    guard let front = situation.front else {
        // An acquire and a new render state can arrive together: a first engine that is still
        // starting is redirected rather than joined by a second one.
        if let starting = situation.incoming { return CrossfadePlan(start: .redirect(starting)) }
        return CrossfadePlan(
            start: .fresh(.lower),
            clears: .lower,
            before: [OpacityChange(.upper, 0)],
            whenReady: [OpacityChange(.lower, 1)]
        )
    }
    if situation.incoming != nil { return CrossfadePlan(start: .afterCrossfade) }
    guard crossfade else { return CrossfadePlan(start: .inPlace(front)) }

    switch front {
    case .lower:
        // The new video fades in on top of the old one, which stays opaque underneath.
        return CrossfadePlan(
            start: .fresh(.upper),
            clears: .upper,
            before: [OpacityChange(.upper, 0)],
            fade: OpacityChange(.upper, 1),
            stops: .lower
        )
    case .upper:
        // The new video starts underneath, already opaque, and the old one fades out above it.
        return CrossfadePlan(
            start: .fresh(.lower),
            clears: .lower,
            before: [OpacityChange(.lower, 1)],
            fade: OpacityChange(.upper, 0),
            stops: .upper
        )
    }
}
