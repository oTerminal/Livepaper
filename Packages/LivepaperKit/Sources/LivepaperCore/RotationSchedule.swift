import Foundation

/// What the rotation schedule changed: the state to commit, and which displays moved.
public struct RotationChange: Equatable, Sendable {
    /// The app state with the change made, for the app model to commit.
    public var state: AppState
    /// The displays a tick, a wake or the login moved on, in the order of their UUIDs.
    public var rotated: [DisplayIdentity]
    /// The displays that count their interval from now: resumed from a pause,
    /// or showing a playlist with no rotation on record, or with one later than now.
    public var counting: [DisplayIdentity]
}

/// The rotation driver's decisions: which displays rotation moves, when the
/// next tick falls due, and what a tick, a wake, the login and a resume do.
/// The driver holds the clock and the timer; everything it decides is here.
///
/// The app state's `rotation` is all that rotation remembers. Each display's
/// `lastRotation` is when its interval started, so a relaunch carries on the
/// pass where it was, and the login is told from a relaunch by it: no second file.
///
/// Rotation moves a display that is connected, shows a playlist and is not
/// paused, by its own pause or by Pause All. Pause rules (battery, a covered
/// desktop, a lock and the rest) do not hold rotation: they stop the video,
/// not the playlist. A paused display counts its interval again from the
/// moment it resumes, so its next rotation is an interval after that. Next
/// is the app model's (`RotationHistories.next`) and works on a paused display.
public struct RotationSchedule: Equatable, Sendable {
    /// A wake does not move a display that rotated this recently: a timer that
    /// fell due while the Mac slept fires as it wakes, often before the wake
    /// is heard, and that display has just moved on.
    public static let wakeAfterRotation: Duration = .seconds(10)

    /// The state as the app holds it, with every change answered since.
    public private(set) var state: AppState
    public private(set) var connected: [DisplayIdentity]
    public private(set) var isPausedAll: Bool
    /// The displays a pause held at the last change, so that a resume is seen.
    private var held: Set<DisplayIdentity>

    public init(state: AppState, connected: [DisplayIdentity], isPausedAll: Bool) {
        self.state = state
        self.connected = connected
        self.isPausedAll = isPausedAll
        held = Self.held(state: state, connected: connected, isPausedAll: isPausedAll)
    }

    /// The displays rotation moves now, in the order of their UUIDs.
    public var moving: [DisplayIdentity] {
        guard !isPausedAll else { return [] }
        return Set(connected).sorted(byDisplay: \.self).filter { display in
            !state.pausedDisplays.contains(display) && playlist(shownOn: display) != nil
        }
    }

    /// When the next tick is due: the earliest end of an interval among the
    /// displays rotation moves. Nil when none of them has a rotation on record.
    public var nextTick: Date? {
        moving.compactMap(dueDate(of:)).min()
    }

    // MARK: Events

    /// The app's state, its connected displays or Pause All changed. A display
    /// a pause no longer holds counts from `now`, and so does one first seen
    /// showing a playlist with no rotation on record (All Displays set while
    /// it was unplugged), rather than rotating at once.
    public mutating func change(state: AppState, connected: [DisplayIdentity], isPausedAll: Bool, at now: Date) -> RotationChange? {
        self.state = state
        self.connected = connected
        self.isPausedAll = isPausedAll
        let held = Self.held(state: state, connected: connected, isPausedAll: isPausedAll)
        let resumed = self.held.subtracting(held)
        self.held = held
        return finish(rotated: [], resumed: resumed, at: now)
    }

    /// The timer fired: the displays whose interval has passed move on.
    public mutating func tick(at now: Date, rng: inout some RandomNumberGenerator) -> RotationChange? {
        let due = moving.filter { display in dueDate(of: display).map { $0 <= now } ?? false }
        return rotate(due, .tick(at: now), rng: &rng)
    }

    /// The Mac woke: every display rotation moves moves on, but for one that
    /// rotated in the last `wakeAfterRotation`.
    public mutating func wake(at now: Date, rng: inout some RandomNumberGenerator) -> RotationChange? {
        let displays = moving.filter { display in
            guard let last = state.rotation[display]?.lastRotation else { return true }
            return now.elapsed(since: last) >= Self.wakeAfterRotation
        }
        return rotate(displays, .wake(at: now), rng: &rng)
    }

    /// The app launched: each display rotation moves that last rotated before
    /// the session started moves on, once. A relaunch in the same session
    /// finds its last rotation after the start, and moves nothing.
    public mutating func login(sessionStart: Date, at now: Date, rng: inout some RandomNumberGenerator) -> RotationChange? {
        let displays = moving.filter { display in
            guard let last = state.rotation[display]?.lastRotation else { return false }
            return last < sessionStart
        }
        return rotate(displays, .login(at: now), rng: &rng)
    }

    // MARK: Helpers

    private mutating func rotate(
        _ displays: [DisplayIdentity], _ event: RotationEvent, rng: inout some RandomNumberGenerator
    ) -> RotationChange? {
        var rotated: [DisplayIdentity] = []
        for display in displays {
            state = state.rotating(display, event, rng: &rng)
            if state.rotation[display]?.lastRotation == event.date { rotated.append(display) }
        }
        return finish(rotated: rotated, resumed: [], at: event.date)
    }

    /// Every display rotation moves has an interval running once this is done:
    /// one resumed, one with no rotation on record and one whose rotation is
    /// later than now (the clock went back) count from `now`. Answers the
    /// change, or nil when nothing moved and nothing started counting.
    private mutating func finish(rotated: [DisplayIdentity], resumed: Set<DisplayIdentity>, at now: Date) -> RotationChange? {
        let counting = moving.filter { display in
            guard let last = state.rotation[display]?.lastRotation else { return true }
            return resumed.contains(display) || last > now
        }
        for display in counting {
            var rotation = state.rotation[display] ?? RotationState()
            rotation.lastRotation = now
            state.rotation[display] = rotation
        }
        guard !rotated.isEmpty || !counting.isEmpty else { return nil }
        return RotationChange(state: state, rotated: rotated, counting: counting)
    }

    private func playlist(shownOn display: DisplayIdentity) -> Playlist? {
        guard case .playlist(let id)? = state.assignment(for: display) else { return nil }
        return state[playlist: id]
    }

    /// The first moment a tick finds the display's interval passed, by the
    /// arithmetic `nextRotation` uses. A date plus an interval does not always
    /// come back as the same interval, and a timer set a hair too early would
    /// move nothing and fall due again at once.
    private func dueDate(of display: DisplayIdentity) -> Date? {
        guard let playlist = playlist(shownOn: display), let last = state.rotation[display]?.lastRotation else { return nil }
        var due = last.addingTimeInterval(playlist.interval / .seconds(1))
        while due.elapsed(since: last) < playlist.interval {
            due = Date(timeIntervalSinceReferenceDate: due.timeIntervalSinceReferenceDate.nextUp)
        }
        return due
    }

    /// The displays a pause holds: the user's, and under Pause All every connected one.
    private static func held(state: AppState, connected: [DisplayIdentity], isPausedAll: Bool) -> Set<DisplayIdentity> {
        isPausedAll ? state.pausedDisplays.union(connected) : state.pausedDisplays
    }
}
