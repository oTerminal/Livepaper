import Foundation
import LivepaperCore

/// What one surface should be doing, from the render state and the playback policy.
public enum SurfaceTarget: Equatable, Sendable {
    /// No render state, or none for this surface's display: the neutral colour.
    case nothing
    /// The stopped render state: the poster, and no decoder.
    case still(SurfaceWallpaper)
    /// The wallpaper, played, paused or suspended as the policy decided.
    case playback(SurfaceWallpaper, PlaybackDecision)
}

/// A display's decision, whichever wallpaper it is about: what the supervisor
/// logs when it changes, so that a new wallpaper played the same way is not a
/// new decision.
enum DisplayDecision: Equatable {
    case nothing
    case still
    case playback(PlaybackDecision)

    init(_ target: SurfaceTarget) {
        switch target {
        case .nothing: self = .nothing
        case .still: self = .still
        case .playback(_, let decision): self = .playback(decision)
        }
    }
}

/// One call on a `SurfacePlayback`.
public enum SurfaceCall: Equatable, Sendable {
    case show(SurfaceWallpaper, crossfade: Bool)
    case holdStill(SurfaceWallpaper)
    case showNothing
    case pause
    case resume
    case suspend
}

/// The calls that take a surface from what it is doing to `target`.
///
/// Pause and suspend only ever stop what is up: a surface with nothing up, or
/// a different wallpaper, holds the poster instead of opening a video just to
/// stop it. Only a surface that plays crossfades to another video; anything
/// else switches without a fade. `show` leaves the surface playing, so
/// nothing follows it but a pause.
public func surfaceCalls(
    toReach target: SurfaceTarget, from state: SurfacePlaybackState, showing current: SurfaceWallpaper?
) -> [SurfaceCall] {
    switch target {
    case .nothing: state == .nothing ? [] : [.showNothing]
    case .still(let wallpaper): holding(wallpaper, from: state, showing: current)
    case .playback(let wallpaper, .play): playing(wallpaper, from: state, showing: current)
    case .playback(let wallpaper, .pause): pausing(wallpaper, from: state, showing: current)
    case .playback(let wallpaper, .suspend): suspending(wallpaper, from: state, showing: current)
    }
}

/// The poster, unless that very still is up.
private func holding(
    _ wallpaper: SurfaceWallpaper, from state: SurfacePlaybackState, showing current: SurfaceWallpaper?
) -> [SurfaceCall] {
    state == .still && looksTheSame(current, wallpaper) ? [] : [.holdStill(wallpaper)]
}

private func playing(
    _ wallpaper: SurfaceWallpaper, from state: SurfacePlaybackState, showing current: SurfaceWallpaper?
) -> [SurfaceCall] {
    switch state {
    case .nothing, .still: [.show(wallpaper, crossfade: false)]
    case .playing where current == wallpaper: []
    case .playing: [.show(wallpaper, crossfade: current?.video != wallpaper.video)]
    case .paused, .suspended: current == wallpaper ? [.resume] : [.show(wallpaper, crossfade: false)]
    }
}

private func pausing(
    _ wallpaper: SurfaceWallpaper, from state: SurfacePlaybackState, showing current: SurfaceWallpaper?
) -> [SurfaceCall] {
    if state == .nothing || state == .still { return holding(wallpaper, from: state, showing: current) }
    guard current?.video == wallpaper.video else { return [.holdStill(wallpaper)] }
    guard looksTheSame(current, wallpaper) else { return [.show(wallpaper, crossfade: false), .pause] }
    switch state {
    case .playing: return [.pause]
    // The readers went with the suspend: open them again, so that a picture is up.
    case .suspended: return [.resume, .pause]
    default: return []
    }
}

private func suspending(
    _ wallpaper: SurfaceWallpaper, from state: SurfacePlaybackState, showing current: SurfaceWallpaper?
) -> [SurfaceCall] {
    if state == .nothing || state == .still { return holding(wallpaper, from: state, showing: current) }
    guard looksTheSame(current, wallpaper) else { return [.holdStill(wallpaper)] }
    return state == .suspended ? [] : [.suspend]
}

/// When `decision` is to be taken again because the sensed conditions behind
/// it expire, or `nil` when nothing but a new render state can change it.
///
/// Only a pause or suspend that a sensed condition caused expires: the user's
/// pause never does, and conditions that play go on playing once they are
/// stale. Conditions exactly `PlaybackConditions.expiry` old still count, so
/// this is the first moment after that.
public func decisionExpiry(of decision: PlaybackDecision, conditions: PlaybackConditions) -> Date? {
    switch decision {
    case .play, .pause(.user), .suspend(.user):
        return nil
    case .pause, .suspend:
        let boundary = conditions.sensedAt.addingTimeInterval(PlaybackConditions.expiry / .seconds(1))
        return Date(timeIntervalSinceReferenceDate: boundary.timeIntervalSinceReferenceDate.nextUp)
    }
}

extension SurfaceWallpaper {
    /// A display's wallpaper from the render state, its paths resolved inside the library.
    public init(_ display: RenderState.Display, in location: LibraryLocation) {
        self.init(
            wallpaper: display.wallpaper,
            video: location.url(for: display.optimisedCopy),
            poster: location.url(for: display.poster),
            presentation: display.presentation,
            volume: display.volume,
            scene: display.scene.map { SurfaceScene(folder: location.url(for: $0.project).deletingLastPathComponent(), size: $0.size) }
        )
    }
}

/// The same picture on screen: only the volume may differ.
private func looksTheSame(_ current: SurfaceWallpaper?, _ wallpaper: SurfaceWallpaper) -> Bool {
    guard let current else { return false }
    return current.video == wallpaper.video && current.poster == wallpaper.poster && current.presentation == wallpaper.presentation
}
