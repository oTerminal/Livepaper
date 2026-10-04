import Foundation
import LivepaperCore

/// The wording of the host client's log lines, under `LivepaperSystem.logSubsystem`,
/// category `host`. Other tools read them (the soak's parser, the release checklist),
/// so the wording lives here, in one place.
nonisolated public enum HostLog {
    public static let category = "host"

    public static let activated = "host: activated, waiting for the extension's heartbeat"

    public static func status(_ status: RenderHostStatus) -> String {
        "host: status \(status.name)"
    }

    public static func silence(_ level: RecoveryLevel) -> String {
        "host: no heartbeat, asking the extension to \(String(describing: level))"
    }

    public static func skipped(_ level: RecoveryLevel) -> String {
        "host: no heartbeat since activation, skipping \(String(describing: level)): no extension to receive it"
    }

    public static func recover(_ level: RecoveryLevel) -> String {
        "host: asking the extension to \(String(describing: level))"
    }

    public static func restarting(_ reason: AgentRestartReason) -> String {
        "host: restarting WallpaperAgent (\(name(of: reason)))"
    }

    public static func restarted(_ outcome: AgentRestartOutcome) -> String {
        switch outcome {
        case .restarted(let previous, let current):
            "host: WallpaperAgent restarted, pid \(previous) -> \(current)"
        case .notBack(let previous):
            "host: WallpaperAgent pid \(previous) signalled, not back yet"
        case .notRunning:
            "host: WallpaperAgent is not running, nothing to restart"
        case .signalFailed(let pid, let errno):
            "host: could not signal WallpaperAgent pid \(pid), errno \(errno)"
        }
    }

    public static func refused(_ reason: AgentRestartReason, _ refusal: AgentRestartRefusal) -> String {
        switch refusal {
        case .tooSoon(let allowedFrom):
            "host: not restarting WallpaperAgent (\(name(of: reason))): restarted less than 10 minutes ago, "
                + "allowed from \(allowedFrom.formatted(.iso8601))"
        case .awaitingHeartbeat:
            "host: not restarting WallpaperAgent (\(name(of: reason))): no heartbeat since the last restart"
        }
    }

    public static func renderStateWritten(_ state: RenderState) -> String {
        "host: render state \(state.generation) written\(state.isStopped ? ", stopped" : "")"
    }

    public static func renderStateNotWritten(_ state: RenderState, _ error: any Error) -> String {
        "host: render state \(state.generation) not written: \(error)"
    }

    public static let nothingToStop = "host: no render state to stop"

    public static func playbackMetrics(_ on: Bool) -> String {
        "host: playback metrics \(on ? "on" : "off")"
    }

    public static let checkRequested = "host: check requested"

    public static func name(of reason: AgentRestartReason) -> String {
        switch reason {
        case .silence: "silence"
        case .spiral: "spiral"
        case .watchdog: "watchdog"
        case .user: "user"
        }
    }
}

/// The wording of the sensing log lines, under `LivepaperSystem.logSubsystem`, category `sensing`.
nonisolated public enum SensingLog {
    public static let category = "sensing"

    /// Every new `SensedConditions`, change or refresh. Display sets are sorted, so the line is stable.
    public static func conditions(_ conditions: SensedConditions) -> String {
        "sensing: covered [\(list(conditions.coveredDisplays))] asleep [\(list(conditions.asleepDisplays))] "
            + "locked \(conditions.locked) lowPowerMode \(conditions.lowPowerMode) onBattery \(conditions.onBattery)"
    }

    private static func list(_ displays: Set<DisplayIdentity>) -> String {
        displays.map(\.description).sorted().joined(separator: ", ")
    }
}
