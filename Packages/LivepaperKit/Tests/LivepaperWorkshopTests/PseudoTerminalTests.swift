import Foundation
import Testing
@testable import LivepaperWorkshop

/// The pty driver's signals: sent to steamcmd's process group while it is
/// there, and never once it has been reaped, when its number may be another's.
struct PseudoTerminalTests {
    static func start(_ script: String) throws -> PseudoTerminalProcess {
        try PseudoTerminalProcess.start(
            executable: URL(filePath: "/bin/sh"), arguments: ["-c", script], environment: [:], directory: URL(filePath: "/tmp")
        )
    }

    /// Waits for its exit, which comes once it has been reaped.
    static func exit(of process: PseudoTerminalProcess) async -> Int32? {
        for await event in process.events {
            if case .exited(let status) = event { return status }
        }
        return nil
    }

    @Test func `a running process is stopped, and its exit says by what`() async throws {
        let process = try Self.start("sleep 30")
        #expect(process.kill())
        #expect(await Self.exit(of: process) == 128 + SIGKILL)
    }

    @Test func `nothing is sent to a process once it has been reaped, since its number may be another's`() async throws {
        let process = try Self.start("exit 0")
        #expect(await Self.exit(of: process) == 0)

        #expect(!process.kill())
        #expect(!process.terminate())
    }

    @Test func `terminate insists only while the process is still there`() async throws {
        // It ignores the polite request, so only the insisting ends it.
        let process = try Self.start("trap '' TERM; sleep 30")
        try await Task.sleep(for: .milliseconds(200))
        #expect(process.terminate())
        #expect(await Self.exit(of: process) == 128 + SIGKILL)
    }
}
