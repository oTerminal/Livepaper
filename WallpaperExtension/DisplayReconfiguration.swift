import CoreGraphics
import Foundation
import LivepaperCore
import LivepaperPlayback

/// A display's mode changed. WallpaperAgent sends nothing and stretches the
/// old surface into the new size, each axis on its own, so the extension
/// watches CoreGraphics itself and has the supervisor lay the display's desktop
/// surfaces out again.
///
/// A change comes as several callbacks, which are taken together once they
/// have been quiet for `settle`. Each display is compared with the geometry
/// CoreGraphics gave when its surfaces were acquired or last laid out, not with
/// the agent's, so that a change in the arrangement or a wake, which leave the
/// mode as it was, lay nothing out again.
final class DisplayReconfiguration {
    static let settle: Duration = .milliseconds(500)

    private let hosted: HostedSurfaces
    private let supervisor: PlaybackSupervisor
    private var settling: Task<Void, Never>?

    init(hosted: HostedSurfaces, supervisor: PlaybackSupervisor) {
        self.hosted = hosted
        self.supervisor = supervisor
    }

    /// CoreGraphics is handed this object unretained: it lives as long as the
    /// extension, and `deinit` takes the callback back.
    func start() {
        let status = CGDisplayRegisterReconfigurationCallback(displayReconfigured, Unmanaged.passUnretained(self).toOpaque())
        if status != .success {
            ExtensionLog.error(.cannotWatchReconfiguration(status.rawValue))
        }
    }

    deinit {
        CGDisplayRemoveReconfigurationCallback(displayReconfigured, Unmanaged.passUnretained(self).toOpaque())
    }

    fileprivate func reconfigured() {
        settling?.cancel()
        settling = Task {
            do { try await Task.sleep(for: Self.settle) } catch { return }
            self.settling = nil
            self.settled()
        }
    }

    private func settled() {
        for (display, surfaces) in hosted.desktopSurfacesByDisplay(asking: supervisor) {
            guard let id = Displays.display(with: display), let geometry = Displays.geometry(of: id) else { continue }
            let old = surfaces.first?.displayGeometry
            guard geometry != old else { continue }
            ExtensionLog.notice(.displayReconfigured(display, from: old, to: geometry))
            for surface in surfaces {
                surface.displayGeometry = geometry
                surface.geometry = geometry
            }
            supervisor.layout(display: display, geometry: geometry)
        }
    }
}

/// CoreGraphics calls this before and after each change of each display, with
/// the observer in `userInfo`. Only the after is wanted.
private nonisolated func displayReconfigured(
    _ display: CGDirectDisplayID,
    _ flags: CGDisplayChangeSummaryFlags,
    _ userInfo: UnsafeMutableRawPointer?
) {
    guard !flags.contains(.beginConfigurationFlag), let userInfo else { return }
    let observer = Unmanaged<DisplayReconfiguration>.fromOpaque(userInfo).takeUnretainedValue()
    DispatchQueue.main.async { observer.reconfigured() }
}
