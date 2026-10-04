import LivepaperCore

/// Every line `PlaybackSupervisor` logs, worded here and nowhere else. Other
/// tools parse them (the soak's parser, the release checklist), so
/// each is `key=value` after a fixed phrase, and `SupervisorLogTests` pins them.
/// A recovery level or a pause reason is an enum without payloads, which
/// prints as its case name (`flush`, `desktopCovered`): that is its wording.
public enum SupervisorLog {
    /// What every line about one surface carries.
    public struct Surface: Equatable, Sendable {
        public var surface: SurfaceID
        public var display: DisplayIdentity
        public var isPreview: Bool
        /// The wallpaper it shows or is about to, if any.
        public var wallpaper: WallpaperID?
        /// The render state's generation, if one has been read.
        public var generation: UInt64?

        public init(surface: SurfaceID, display: DisplayIdentity, isPreview: Bool, wallpaper: WallpaperID?, generation: UInt64?) {
            self.surface = surface
            self.display = display
            self.isPreview = isPreview
            self.wallpaper = wallpaper
            self.generation = generation
        }

        var fields: String {
            let wallpaper = wallpaper?.description ?? "none"
            let generation = generationText(generation)
            return "surface=\(surface) display=\(display) preview=\(isPreview) wallpaper=\(wallpaper) generation=\(generation)"
        }
    }

    // MARK: Surface events

    public static func acquired(_ surface: Surface, reused: Bool) -> String {
        "acquire \(reused ? "reused" : "new") \(surface.fields)"
    }

    public static func invalidated(_ surface: Surface) -> String {
        "invalidate \(surface.fields)"
    }

    public static func invalidatedUnknown(_ surface: SurfaceID) -> String {
        "invalidate unknown surface=\(surface)"
    }

    public static func tornDown(_ surface: Surface) -> String {
        "torn down \(surface.fields)"
    }

    public static func nowShowing(_ surface: Surface, crossfade: Bool) -> String {
        "now showing \(surface.fields) crossfade=\(crossfade)"
    }

    public static func holdingStill(_ surface: Surface) -> String {
        "holding still \(surface.fields)"
    }

    public static func showingNothing(_ surface: Surface) -> String {
        "showing nothing \(surface.fields)"
    }

    public static func updated(_ surface: Surface, mode: SurfaceMode) -> String {
        "update \(surface.fields) mode=\(mode.rawValue)"
    }

    // MARK: Decisions and the render state

    public static func decision(display: DisplayIdentity, target: SurfaceTarget, generation: UInt64?) -> String {
        "decision display=\(display) decision=\(name(of: DisplayDecision(target))) generation=\(generationText(generation))"
    }

    /// `kept` is the generation still shown when the file cannot be trusted.
    public static func renderState(_ read: RenderStateRead, kept: UInt64?) -> String {
        switch read {
        case .read(let state):
            "render state read generation=\(state.generation) stopped=\(state.isStopped) displays=\(state.displays.count)"
        case .missing: "render state missing, showing nothing"
        case .unreadable(let reason): "render state unreadable, keeping generation=\(generationText(kept)): \(reason)"
        }
    }

    // MARK: The watchdog

    public static func checkStarted(_ trigger: WatchdogTrigger, judging count: Int) -> String {
        "check started reason=\(trigger.rawValue) surfaces=\(count)"
    }

    /// `fed` is the frames the engine fed the renderer over the same window. A
    /// scene's adds what its display link asked for, what the window server
    /// presented, and `withheld` when the link asked for too few while the engine stood ready.
    public static func counted(_ surface: Surface, _ count: PictureCount) -> String {
        var scene = count.asked.map { " asked=\($0)" } ?? ""
        scene += count.presented.map { " presented=\($0)" } ?? ""
        if count.withheld { scene += " withheld" }
        return "check count \(surface.fields) displayed=\(count.displayed) expected=\(count.expected) fed=\(count.fed)" + scene
    }

    /// `attempt` is how many recoveries had been tried on the surface before this verdict.
    public static func verdict(_ surface: Surface, _ step: WatchdogStep, attempt: Int) -> String {
        let verdict = switch step {
        case .healthy: "healthy"
        case .notComposited: "notComposited"
        case .recover(let level): String(describing: level)
        case .requestRestart: String(describing: RecoveryLevel.restartAgent)
        }
        return "check verdict \(surface.fields) verdict=\(verdict) attempt=\(attempt)"
    }

    public static func recoveryTried(_ surface: Surface, level: RecoveryLevel) -> String {
        "recovery tried \(surface.fields) level=\(String(describing: level))"
    }

    /// The heartbeat now carries `restartAgentRequested`.
    public static func restartRequested(_ surface: Surface) -> String {
        "restart requested \(surface.fields)"
    }

    /// The heartbeat no longer carries `restartAgentRequested`.
    public static let restartRequestCleared = "restart request cleared"

    /// The app's `HostNotification.recover`.
    public static func recoverRequested(_ level: RecoveryLevel, stalled count: Int) -> String {
        "recover requested level=\(String(describing: level)) stalled=\(count)"
    }

    // MARK: Names

    private static func name(of decision: DisplayDecision) -> String {
        switch decision {
        case .nothing: "nothing"
        case .still: "still"
        case .playback(.play): "play"
        case .playback(.pause(let reason)): "pause.\(String(describing: reason))"
        case .playback(.suspend(let reason)): "suspend.\(String(describing: reason))"
        }
    }
}

/// A generation, or `none` before any render state was read.
private func generationText(_ generation: UInt64?) -> String {
    generation.map(String.init) ?? "none"
}
