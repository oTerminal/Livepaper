import Darwin
import Foundation
import Synchronization

/// A process whose standard input, output and error are one pseudo-terminal,
/// as if it ran in Terminal.
///
/// steamcmd reads the password from its terminal and prints its prompts
/// without a line ending, so it is driven through a pty rather than pipes.
/// Echo is switched off before it starts, so nothing typed, the password
/// included, ever comes back as output. It starts in a session of its own and
/// inherits no other descriptor, and stopping it stops its process group, but
/// only until it has been reaped: after that its number, and its group's, may
/// be another process's.
final class PseudoTerminalProcess: Sendable {
    enum Event: Sendable {
        case output(Data)
        /// Its exit status, or 128 plus the signal that ended it.
        case exited(Int32)
    }

    enum StartError: Error, Equatable {
        /// The executable is for another architecture: an Intel binary with no Rosetta (`EBADARCH`).
        case wrongArchitecture
        case failed(errno: Int32)
    }

    let pid: pid_t
    let events: AsyncStream<Event>
    private let controller: Controller
    private let child: Child

    private init(child: Child, controller: Controller, events: AsyncStream<Event>) {
        pid = child.pid
        self.child = child
        self.controller = controller
        self.events = events
    }

    /// Starts it. Nothing reaches it but the arguments, the environment given and what is typed into it.
    static func start(
        executable: URL, arguments: [String], environment: [String: String], directory: URL
    ) throws(StartError) -> PseudoTerminalProcess {
        var controller: Int32 = -1
        var terminal: Int32 = -1
        var size = winsize(ws_row: 50, ws_col: 200, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&controller, &terminal, nil, nil, &size) == 0 else { throw .failed(errno: errno) }
        defer { close(terminal) }
        _ = fcntl(controller, F_SETFD, FD_CLOEXEC)

        var settings = termios()
        tcgetattr(terminal, &settings)
        settings.c_lflag &= ~tcflag_t(ECHO | ECHONL)
        tcsetattr(terminal, TCSANOW, &settings)

        let owner = Controller(controller)
        let pid: pid_t
        do {
            pid = try spawn(executable, arguments, environment, directory, terminal: terminal)
        } catch {
            owner.close()
            throw error
        }
        let (events, continuation) = AsyncStream.makeStream(of: Event.self, bufferingPolicy: .unbounded)
        let child = Child(pid)
        follow(child, controller: owner, into: continuation)
        return PseudoTerminalProcess(child: child, controller: owner, events: events)
    }

    /// Types text into its terminal.
    func type(_ text: String) {
        controller.write(text)
    }

    /// Asks it to go, then insists two seconds later if it is still there.
    /// Answers whether it was still there to ask.
    @discardableResult
    func terminate() -> Bool {
        guard child.signal(SIGTERM) else { return false }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [child] in
            child.signal(SIGKILL)
        }
        return true
    }

    /// Ends it, and anything it started, at once. Answers whether it was still there to end.
    @discardableResult
    func kill() -> Bool {
        child.signal(SIGKILL)
    }

    // MARK: Starting

    private static func spawn(
        _ executable: URL, _ arguments: [String], _ environment: [String: String], _ directory: URL, terminal: Int32
    ) throws(StartError) -> pid_t {
        var actions: posix_spawn_file_actions_t?
        posix_spawn_file_actions_init(&actions)
        defer { posix_spawn_file_actions_destroy(&actions) }
        for descriptor in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] {
            posix_spawn_file_actions_adddup2(&actions, terminal, descriptor)
        }
        posix_spawn_file_actions_addchdir(&actions, directory.path)

        var attributes: posix_spawnattr_t?
        posix_spawnattr_init(&attributes)
        defer { posix_spawnattr_destroy(&attributes) }
        // A session of its own, no descriptor but the three above, and every signal at its default and unblocked.
        let flags = POSIX_SPAWN_SETSID | POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSIGDEF | POSIX_SPAWN_SETSIGMASK
        posix_spawnattr_setflags(&attributes, Int16(flags))
        var all = sigset_t()
        sigfillset(&all)
        posix_spawnattr_setsigdefault(&attributes, &all)
        var none = sigset_t()
        sigemptyset(&none)
        posix_spawnattr_setsigmask(&attributes, &none)

        let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        let envp = environment.sorted { $0.key < $1.key }.map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer { (argv + envp).forEach { free($0) } }

        var pid: pid_t = 0
        let result = posix_spawn(&pid, executable.path, &actions, &attributes, argv, envp)
        switch result {
        case 0: return pid
        case EBADARCH: throw .wrongArchitecture
        default: throw .failed(errno: result)
        }
    }

    /// Reads its output on a thread of its own, and waits for it on another:
    /// both block, and Swift's own threads are not for blocking on. Its exit is
    /// the last event, after everything it printed.
    private static func follow(_ child: Child, controller: Controller, into continuation: AsyncStream<Event>.Continuation) {
        let readingDone = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            var buffer = [UInt8](repeating: 0, count: 16_384)
            while true {
                let count = buffer.withUnsafeMutableBytes { read(controller.descriptor, $0.baseAddress, $0.count) }
                if count > 0 {
                    continuation.yield(.output(Data(buffer[..<count])))
                } else if count < 0, errno == EINTR {
                    continue
                } else {
                    // End of file, or EIO once the last holder of the terminal has gone.
                    break
                }
            }
            controller.close()
            readingDone.signal()
        }
        Thread.detachNewThread {
            let status = child.waitAndReap()
            // What it printed last arrives first. Something it started may still hold the terminal: not for long.
            _ = readingDone.wait(timeout: .now() + 1)
            continuation.yield(.exited(exitStatus(status)))
            continuation.finish()
        }
    }

    /// `WEXITSTATUS`, or 128 plus `WTERMSIG`, which Swift does not import.
    private static func exitStatus(_ status: Int32) -> Int32 {
        let signal = status & 0x7F
        return signal == 0 ? (status >> 8) & 0xFF : 128 + signal
    }
}

/// The process started, and whether it has been reaped. A signal is sent to its
/// group only while it has not: until then the system keeps its number, and so
/// its group's, from any other process.
private final class Child: Sendable {
    let pid: pid_t
    private let reaped = Mutex(false)

    init(_ pid: pid_t) {
        self.pid = pid
    }

    /// Sends the signal to its process group unless it has been reaped. Answers whether it was sent.
    @discardableResult
    func signal(_ signal: Int32) -> Bool {
        reaped.withLock { reaped in
            guard !reaped else { return false }
            killpg(pid, signal)
            return true
        }
    }

    /// Blocks until it exits, then reaps it under the lock `signal` takes, so
    /// that no signal can go out between the reaping and its being known.
    /// Answers its wait status.
    func waitAndReap() -> Int32 {
        // Waiting without reaping leaves its number held while the lock is taken.
        var info = siginfo_t()
        while waitid(P_PID, id_t(pid), &info, WEXITED | WNOWAIT) < 0, errno == EINTR {}
        return reaped.withLock { reaped in
            var status: Int32 = 0
            while waitpid(pid, &status, 0) < 0, errno == EINTR {}
            reaped = true
            return status
        }
    }
}

/// The pty's controlling side. The reader closes it once the process has gone,
/// and nothing is written after that, so a descriptor number the system has
/// handed out again is never written to.
private final class Controller: Sendable {
    let descriptor: Int32
    private let isOpen = Mutex(true)

    init(_ descriptor: Int32) {
        self.descriptor = descriptor
    }

    func write(_ text: String) {
        isOpen.withLock { isOpen in
            guard isOpen else { return }
            var bytes = Array(text.utf8)[...]
            while !bytes.isEmpty {
                let written = bytes.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
                if written < 0, errno == EINTR { continue }
                guard written > 0 else { return }
                bytes = bytes.dropFirst(written)
            }
        }
    }

    func close() {
        isOpen.withLock { isOpen in
            guard isOpen else { return }
            isOpen = false
            Darwin.close(descriptor)
        }
    }
}
