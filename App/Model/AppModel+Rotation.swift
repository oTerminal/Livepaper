import Foundation
import LivepaperCore
import LivepaperSystem

// Rotation: the driver moves each display's playlist on at the end of its
// interval, when the Mac wakes, and once a session at login. What it decides
// is `RotationSchedule`'s; it holds the one timer and hands each new state to
// the model, which makes it like any other change. The model tells it of
// every change to the state, the displays and Pause All.

extension AppModel {
    /// At the launch, once the library is read. A library that could not be
    /// read is not written to, so nothing rotates then.
    func makeRotationDriver() {
        guard libraryProblem == nil else { return }
        rotationDriver = RotationDriver(sleep: services.sleep) { [weak self] next in
            self?.rotated(to: next)
        }
    }

    /// The displays changed. The first time, the driver starts: a display that
    /// last rotated before this session began rotates now, once. Called before
    /// the render state is made, so that the first one carries that rotation.
    func rotationFollowsDisplays(isFirst: Bool) {
        guard isFirst else { return updateRotation() }
        rotationDriver?.launch(
            state: state, connected: displays.map(\.identity), isPausedAll: isPausedAll, sessionStart: SessionStart.current()?.date
        )
    }

    /// The state, the displays or Pause All changed: the driver sets its timer again.
    func updateRotation() {
        rotationDriver?.update(state: state, connected: displays.map(\.identity), isPausedAll: isPausedAll)
    }

    /// At quit: nothing rotates, and Restart's clock stops.
    func stopRotationAndRestart() {
        rotationDriver?.stop()
        serviceRestartTick?.cancel()
    }

    /// A tick, a wake or the login moved playlists on: what each display left
    /// is kept for Previous, as after Next, and the change is made like any other.
    private func rotated(to next: AppState) {
        histories.rotated(from: state, to: next, library: library)
        commit(state: next)
    }
}
