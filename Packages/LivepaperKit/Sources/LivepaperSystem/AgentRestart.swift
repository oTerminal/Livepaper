import Darwin
import Foundation

/// What became of one restart of WallpaperAgent.
nonisolated public enum AgentRestartOutcome: Equatable, Sendable {
    /// launchd brought the agent back as a new process.
    case restarted(previous: Int32, current: Int32)
    /// The agent took the signal and was not back when the wait ended.
    case notBack(previous: Int32)
    /// No WallpaperAgent was running for this user, so nothing was signalled.
    case notRunning
    case signalFailed(pid: Int32, errno: Int32)
}

/// Restarts WallpaperAgent. Injected, so that tests restart nothing.
public protocol AgentRestarting: AnyObject {
    /// Sends the agent one signal and waits for launchd to bring it back. One
    /// call is one signal, never a burst: several
    /// kills within a second make launchd kill the agent it has just respawned
    /// and back off.
    func restartAgent() async -> AgentRestartOutcome
}

/// Finds the current user's WallpaperAgent by name, sends it one `SIGTERM`,
/// and waits a few seconds for launchd to start it again, looking now and then
/// for a new process by the same name. The app is not sandboxed, so it may
/// signal its own user's processes.
public final class WallpaperAgentRestarter: AgentRestarting {
    public static let processName = "WallpaperAgent"
    /// How long to wait for the agent to come back. The spike saw it back at once.
    public static let wait: Duration = .seconds(5)
    private static let look: Duration = .milliseconds(250)

    public init() {}

    public func restartAgent() async -> AgentRestartOutcome {
        guard let previous = Self.agentPID() else { return .notRunning }
        guard kill(previous, SIGTERM) == 0 else { return .signalFailed(pid: previous, errno: errno) }
        var waited = Duration.zero
        while waited < Self.wait {
            try? await Task.sleep(for: Self.look)
            waited += Self.look
            if let current = Self.agentPID(), current != previous {
                return .restarted(previous: previous, current: current)
            }
        }
        return .notBack(previous: previous)
    }

    static func agentPID() -> Int32? {
        processes(ofUser: getuid()).first { $0.name == processName }?.pid
    }

    /// The user's processes, by the short name the kernel keeps for each.
    private static func processes(ofUser user: uid_t) -> [(pid: Int32, name: String)] {
        var query: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_UID, Int32(bitPattern: user)]
        var size = 0
        guard sysctl(&query, UInt32(query.count), nil, &size, nil, 0) == 0, size > 0 else { return [] }
        let stride = MemoryLayout<kinfo_proc>.stride
        // Room for a few processes started between the two calls.
        var table = [kinfo_proc](repeating: kinfo_proc(), count: size / stride + 16)
        size = table.count * stride
        guard sysctl(&query, UInt32(query.count), &table, &size, nil, 0) == 0 else { return [] }
        return table.prefix(size / stride).map { process in
            let name = withUnsafeBytes(of: process.kp_proc.p_comm) { bytes in
                String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8) ?? ""
            }
            return (process.kp_proc.p_pid, name)
        }
    }
}
