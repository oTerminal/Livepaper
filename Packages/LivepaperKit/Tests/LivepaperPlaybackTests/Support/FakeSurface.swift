import LivepaperCore
import LivepaperPlayback

/// Things in the order they happened, with a way to wait until there are enough of them.
///
/// Not `Sendable`: like the supervisor it lives on the test's actor.
final class Journal<Entry> {
    private(set) var entries: [Entry] = []
    private var waiters: [(count: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func append(_ entry: Entry) {
        entries.append(entry)
        let ready = waiters.filter { $0.count <= entries.count }
        waiters.removeAll { $0.count <= entries.count }
        for waiter in ready { waiter.continuation.resume() }
    }

    /// Returns once there are at least `count` entries.
    func wait(for count: Int) async {
        guard entries.count < count else { return }
        await withCheckedContinuation { waiters.append((count, $0)) }
    }
}

/// Holds whatever waits on it until the test opens it.
final class Gate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let waiting = waiters
        waiters = []
        for waiter in waiting { waiter.resume() }
    }
}

/// A surface that draws nothing: its state is what its calls leave, every call
/// is recorded, and its displayed-picture counts are whatever the test says.
final class FakeSurface: SurfacePlayback {
    enum Call: Equatable {
        case playback(SurfaceCall)
        case recover(RecoveryLevel)
        case countPictures
        case layout(SurfaceGeometry)
    }

    private(set) var state = SurfacePlaybackState.nothing
    private(set) var wallpaper: SurfaceWallpaper?
    let calls = Journal<Call>()
    /// What the next counts give, in order. After them, every picture while it plays.
    var counts: [PictureCount?] = []
    /// When set, each count is held until it opens, as a real one is for its window.
    var countGate: Gate?

    var playbackCalls: [SurfaceCall] {
        calls.entries.compactMap { call in
            guard case .playback(let playback) = call else { return nil }
            return playback
        }
    }

    var recoveries: [RecoveryLevel] {
        calls.entries.compactMap { call in
            guard case .recover(let level) = call else { return nil }
            return level
        }
    }

    var countsTaken: Int { calls.entries.filter { $0 == .countPictures }.count }

    /// What the system may do behind the engine's back, as over a sleep: the picture is gone.
    func lose() {
        state = .nothing
        wallpaper = nil
    }

    func show(_ wallpaper: SurfaceWallpaper, crossfade: Bool) async {
        state = .playing
        self.wallpaper = wallpaper
        calls.append(.playback(.show(wallpaper, crossfade: crossfade)))
    }

    func holdStill(poster wallpaper: SurfaceWallpaper) async {
        state = .still
        self.wallpaper = wallpaper
        calls.append(.playback(.holdStill(wallpaper)))
    }

    func showNothing() async {
        state = .nothing
        wallpaper = nil
        calls.append(.playback(.showNothing))
    }

    func pause() async {
        state = .paused
        calls.append(.playback(.pause))
    }

    func resume() async {
        state = .playing
        calls.append(.playback(.resume))
    }

    func suspend() async {
        state = .suspended
        calls.append(.playback(.suspend))
    }

    func recover(_ level: RecoveryLevel) async {
        calls.append(.recover(level))
    }

    func displayedPictures(over window: Duration) async -> PictureCount? {
        calls.append(.countPictures)
        await countGate?.wait()
        if !counts.isEmpty { return counts.removeFirst() }
        return state == .playing ? PictureCount(displayed: 60, expected: 60, fed: 60) : nil
    }

    func layout(surface: SurfaceGeometry) {
        calls.append(.layout(surface))
    }
}
