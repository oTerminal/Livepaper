import Foundation
import LivepaperCore

/// Why the command socket could not be opened. The app logs `kind`, which leaves the path out.
nonisolated public enum CommandServerError: KindNamingError, Equatable, Sendable {
    /// The path does not fit a socket address: `LibraryLocation.commandSocket(fallback:)` avoids it.
    case pathTooLong(URL)
    /// Something that is not a socket is at the path, and is left alone.
    case notASocket(URL)
    /// Another server answers at the path: a second copy of the app.
    case inUse(URL)
    /// A system call failed, with its `errno`.
    case system(String, errno: Int32)

    public var kind: String {
        switch self {
        case .pathTooLong: "the path does not fit a socket address"
        case .notASocket: "something that is not a socket is there"
        case .inUse: "another copy of Livepaper answers there"
        case .system(let call, let errno): "\(call) failed, errno \(errno)"
        }
    }
}

/// The app's end of the command socket, which the `livepaper` tool talks to.
///
/// A Unix stream socket, mode 0600, so only the user's own processes connect.
/// Each connection carries one request line, the command's URL; the server
/// answers one line of JSON (`CommandReply`) and closes. A line that is not a
/// command the socket takes is refused with the reason and never reaches the
/// app; any other goes to `handler` on the main actor, where the app model
/// runs it as it runs every door's commands. Connections are accepted off the
/// main actor and each is read and answered on a thread of its own, so a slow
/// client holds up no one, nor does blocking work elsewhere in the app.
public final class CommandServer {
    /// Runs a command and answers it. It may take as long as the command does:
    /// the diagnostics take a second or two.
    public typealias Handler = @MainActor @Sendable (Command) async -> CommandReply

    nonisolated public struct Limits: Sendable {
        /// The longest request line taken, its line feed aside.
        public var requestBytes: Int
        /// How long a client has, once connected, to send its line.
        public var requestTime: Duration
        /// How long the reply may take to go out before the client is let go.
        public var replyTime: Duration

        public init(requestBytes: Int, requestTime: Duration, replyTime: Duration) {
            self.requestBytes = requestBytes
            self.requestTime = requestTime
            self.replyTime = replyTime
        }

        /// A kilobyte: the longest request, `set` naming a playlist and a display, is 106 bytes.
        public static let standard = Limits(requestBytes: 1024, requestTime: .seconds(5), replyTime: .seconds(5))
    }

    public let socket: URL
    private let limits: Limits
    private let handler: Handler
    private var listener: Listener?

    public init(socket: URL, limits: Limits = .standard, handler: @escaping Handler) {
        self.socket = socket
        self.limits = limits
        self.handler = handler
    }

    public var isRunning: Bool { listener != nil }

    /// Opens the socket and starts accepting. A socket file no one answers on,
    /// left by an app that did not stop, is removed first; anything else at the
    /// path is left alone and throws. The folder must exist.
    public func start() throws(CommandServerError) {
        guard listener == nil else { return }
        listener = try Listener(socket: socket, limits: limits, handler: handler)
    }

    /// Stops accepting and removes the socket file, if it is still this
    /// server's. A connection being answered finishes.
    public func stop() {
        listener?.close()
        listener = nil
    }
}

// MARK: - Listening

/// The listening socket and the source that accepts on it.
nonisolated private final class Listener: Sendable {
    private let socket: URL
    private let source: any DispatchSourceRead
    /// The socket file's identity, so that `close` removes this server's file and no other.
    private let file: (device: dev_t, inode: ino_t)

    init(socket: URL, limits: CommandServer.Limits, handler: @escaping CommandServer.Handler) throws(CommandServerError) {
        guard let address = SocketAddress.make(socket) else { throw .pathTooLong(socket) }
        try Self.removeStale(socket, address: address)

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw .system("socket", errno: errno) }
        // Nothing the app runs (ffmpeg, steamcmd) inherits it, and accept never blocks.
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        guard Self.call(bind, fd, address) == 0 else {
            let error = errno
            Darwin.close(fd)
            throw .system("bind", errno: error)
        }
        // Bound, the file exists but refuses connections until `listen`, so its
        // mode is set before anyone can connect.
        var info = stat()
        do throws(CommandServerError) {
            guard chmod(socket.path, 0o600) == 0 else { throw .system("chmod", errno: errno) }
            guard lstat(socket.path, &info) == 0 else { throw .system("lstat", errno: errno) }
            guard listen(fd, 16) == 0 else { throw .system("listen", errno: errno) }
        } catch {
            Darwin.close(fd)
            unlink(socket.path)
            throw error
        }

        self.socket = socket
        file = (info.st_dev, info.st_ino)
        source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: DispatchQueue(label: "app.livepaper.command-socket"))
        source.setEventHandler {
            // Every connection waiting, until there are none.
            while true {
                let client = accept(fd, nil, nil)
                guard client >= 0 else { return }
                Connection.serve(client, limits: limits, handler: handler)
            }
        }
        source.setCancelHandler { Darwin.close(fd) }
        source.resume()
    }

    deinit {
        close()
    }

    func close() {
        guard !source.isCancelled else { return }
        source.cancel()
        var info = stat()
        if lstat(socket.path, &info) == 0, info.st_dev == file.device, info.st_ino == file.inode {
            unlink(socket.path)
        }
    }

    /// Removes a socket file no one answers on. One that answers is another
    /// server's; anything that is not a socket is not the app's to remove.
    private static func removeStale(_ socket: URL, address: sockaddr_un) throws(CommandServerError) {
        var info = stat()
        guard lstat(socket.path, &info) == 0 else { return }
        guard info.st_mode & S_IFMT == S_IFSOCK else { throw .notASocket(socket) }
        let probe = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard probe >= 0 else { throw .system("socket", errno: errno) }
        defer { Darwin.close(probe) }
        if call(connect, probe, address) == 0 { throw .inUse(socket) }
        guard unlink(socket.path) == 0 || errno == ENOENT else { throw .system("unlink", errno: errno) }
    }

    /// `bind` or `connect` with a Unix-domain address.
    static func call(_ function: (Int32, UnsafePointer<sockaddr>, socklen_t) -> Int32, _ fd: Int32, _ address: sockaddr_un) -> Int32 {
        var address = address
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { function(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
    }
}

// MARK: - One connection

/// One client: its line read, its command run, its reply written, then closed.
nonisolated private enum Connection {
    enum Request {
        case line(String)
        case tooLong
        case timedOut
        case notText
        /// The client went before sending anything.
        case gone
    }

    static func serve(_ client: Int32, limits: CommandServer.Limits, handler: @escaping CommandServer.Handler) {
        _ = fcntl(client, F_SETFD, FD_CLOEXEC)
        _ = fcntl(client, F_SETFL, fcntl(client, F_GETFL) & ~O_NONBLOCK)
        // A client that has gone makes a write fail, rather than end the app with SIGPIPE.
        var on: Int32 = 1
        _ = setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        // A thread of its own, not the shared pool: the read blocks for as long
        // as the client takes, and the pool is held back while other work in the
        // app blocks (on CI's virtual Mac a client waited 7 s for a thread).
        Thread.detachNewThread {
            let reply: CommandReply
            switch read(client, limits: limits) {
            case .line(let line):
                do throws(CommandRejection) {
                    let command = try EntryPoint.commandSocket.command(from: line)
                    Task { @MainActor in
                        let reply = await handler(command)
                        Thread.detachNewThread { finish(client, reply, limits: limits) }
                    }
                    return
                } catch {
                    reply = .refused(error)
                }
            case .tooLong: reply = .refused(reason: "The request is longer than \(limits.requestBytes) bytes")
            case .timedOut: reply = .refused(reason: "No request arrived within \(words(for: limits.requestTime))")
            case .notText: reply = .refused(reason: "The request is not UTF-8 text")
            case .gone:
                Darwin.close(client)
                return
            }
            finish(client, reply, limits: limits)
        }
    }

    /// The request line, read until its line feed or the client's end, within the limits.
    private static func read(_ client: Int32, limits: CommandServer.Limits) -> Request {
        let clock = ContinuousClock()
        let deadline = clock.now + limits.requestTime
        var line: [UInt8] = []
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let remaining = deadline - clock.now
            guard remaining > .zero else { return .timedOut }
            setTimeout(client, SO_RCVTIMEO, remaining)
            let count = Darwin.read(client, &chunk, chunk.count)
            if count < 0 {
                if errno == EINTR { continue }
                return errno == EAGAIN ? .timedOut : .gone
            }
            if count == 0 { return line.isEmpty ? .gone : decoded(line) }
            if let end = chunk[..<count].firstIndex(of: UInt8(ascii: "\n")) {
                line += chunk[..<end]
                return line.count > limits.requestBytes ? .tooLong : decoded(line)
            }
            line += chunk[..<count]
            if line.count > limits.requestBytes { return .tooLong }
        }
    }

    private static func decoded(_ line: [UInt8]) -> Request {
        guard var text = String(validating: line, as: UTF8.self) else { return .notText }
        if text.hasSuffix("\r") { text.removeLast() }
        return .line(text)
    }

    private static func finish(_ client: Int32, _ reply: CommandReply, limits: CommandServer.Limits) {
        defer { Darwin.close(client) }
        guard let bytes = try? reply.line() else { return }
        setTimeout(client, SO_SNDTIMEO, limits.replyTime)
        bytes.withUnsafeBytes { buffer in
            guard let base = buffer.baseAddress else { return }
            var sent = 0
            while sent < buffer.count {
                let count = write(client, base + sent, buffer.count - sent)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { return }
                sent += count
            }
        }
    }

    private static func setTimeout(_ client: Int32, _ option: Int32, _ duration: Duration) {
        let (seconds, attoseconds) = duration.components
        var time = timeval(tv_sec: Int(seconds), tv_usec: Int32(attoseconds / 1_000_000_000_000))
        if time.tv_sec == 0, time.tv_usec == 0 { time.tv_usec = 1 }
        _ = setsockopt(client, SOL_SOCKET, option, &time, socklen_t(MemoryLayout<timeval>.size))
    }

    /// "5 seconds", "0.5 seconds", "1 second".
    private static func words(for duration: Duration) -> String {
        let (seconds, attoseconds) = duration.components
        let value = Double(seconds) + Double(attoseconds) / 1e18
        let number = value == value.rounded() ? String(Int(value)) : String(value)
        return number + (value == 1 ? " second" : " seconds")
    }
}
