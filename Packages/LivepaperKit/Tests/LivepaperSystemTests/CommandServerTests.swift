import Foundation
import LivepaperCore
import LivepaperSystem
import Testing

@MainActor
struct CommandServerTests {
    nonisolated static let studio = DisplayIdentity.numbered(2)

    let folder: SocketFolder
    let socket: URL
    let handled = HandledCommands()

    init() throws {
        folder = try SocketFolder()
        socket = folder.url.appending(path: "command.sock", directoryHint: .notDirectory)
    }

    func server(limits: CommandServer.Limits = .standard, reply: CommandReply = .done(message: nil)) -> CommandServer {
        CommandServer(socket: socket, limits: limits) { [handled] command in
            handled.commands.append(command)
            return reply
        }
    }

    @Test func `a request line is answered with the handler's reply, then the connection closes`() async throws {
        let server = server(reply: .done(message: "Paused"))
        try server.start()
        defer { server.stop() }

        let answer = try await SocketClient.exchange(socket, "livepaper://pause?display=\(Self.studio)\n")

        #expect(try CommandReply(line: answer) == .done(message: "Paused"))
        #expect(handled.commands == [.pause(.display(Self.studio))])
    }

    @Test func `status is answered over the socket`() async throws {
        let report = StatusReport(host: .live, displays: [], wallpapers: [], playlists: [], isPausedAll: true, isMuted: false)
        let server = server(reply: .status(report))
        try server.start()
        defer { server.stop() }

        let answer = try await SocketClient.exchange(socket, "livepaper://status\n")

        #expect(try CommandReply(line: answer) == .status(report))
        #expect(handled.commands == [.status])
    }

    @Test func `a rejected command is refused with its reason, and never reaches the app`() async throws {
        let server = server()
        try server.start()
        defer { server.stop() }

        let answer = try await SocketClient.exchange(socket, "livepaper://set?wallpaper=../x\n")

        #expect(try CommandReply(line: answer) == .refused(CommandRejection.notAUUID(key: "wallpaper", value: "../x")))
        #expect(handled.commands.isEmpty)
    }

    nonisolated static let malformed: [Row<[UInt8], String>] = [
        Row("a line that is not a URL", Array("hello\n".utf8), CommandRejection.notLivepaper.reason),
        Row("an empty line", Array("\n".utf8), CommandRejection.notLivepaper.reason),
        Row("bytes that are not text", [0xFF, 0xFE, 0x0A], "The request is not UTF-8 text"),
    ]

    @Test(arguments: malformed)
    func `a malformed line is refused`(row: Row<[UInt8], String>) async throws {
        let server = server()
        try server.start()
        defer { server.stop() }

        let answer = try await SocketClient.exchange(socket, Data(row.input))

        #expect(try CommandReply(line: answer) == .refused(reason: row.expected))
        #expect(handled.commands.isEmpty)
    }

    @Test func `a line ended by the client's closing its end is still a line`() async throws {
        let server = server()
        try server.start()
        defer { server.stop() }

        let answer = try await SocketClient.exchange(socket, Data("livepaper://mute".utf8))

        #expect(try CommandReply(line: answer) == .done(message: nil))
        #expect(handled.commands == [.mute])
    }

    @Test func `a line over the limit is refused`() async throws {
        let server = server(limits: CommandServer.Limits(requestBytes: 64, requestTime: .seconds(5), replyTime: .seconds(5)))
        try server.start()
        defer { server.stop() }

        let long = "livepaper://set?wallpaper=" + String(repeating: "a", count: 100) + "\n"
        let answer = try await SocketClient.exchange(socket, Data(long.utf8))

        #expect(try CommandReply(line: answer) == .refused(reason: "The request is longer than 64 bytes"))
        #expect(handled.commands.isEmpty)
    }

    @Test func `a client that sends nothing is refused in time, and does not hold up the next`() async throws {
        let server = server(limits: CommandServer.Limits(requestBytes: 1024, requestTime: .milliseconds(500), replyTime: .seconds(5)))
        try server.start()
        defer { server.stop() }
        let clock = ContinuousClock()
        let start = clock.now

        async let silent: (answer: Data, end: ContinuousClock.Instant) = {
            let answer = try await SocketClient.exchange(socket, Data(), closingWrites: false)
            return (answer, clock.now)
        }()
        // The silent client is connected before the prompt one asks.
        try await Task.sleep(for: .milliseconds(100))
        let prompt = try await SocketClient.exchange(socket, "livepaper://library\n")
        let promptEnd = clock.now
        let refused = try await silent

        #expect(try CommandReply(line: prompt) == .done(message: nil))
        #expect(try CommandReply(line: refused.answer) == .refused(reason: "No request arrived within 0.5 seconds"))
        // The clients start and finish on Swift's shared pool, which the rest of
        // the suite keeps busy on CI's virtual Mac: seen there 8 s late, even with
        // a thread per client on the server. Required on a Mac, a known issue there.
        withKnownIssue("a virtual Mac's busy pool delays the test's own clients", isIntermittent: true) {
            #expect(promptEnd < refused.end, "the prompt client was held up until the silent one was refused")
            #expect(refused.end - start < .seconds(3), "the silent client was refused at its limit, not the standard 5 s")
        } when: {
            VirtualMac.isRunning
        }
    }

    @Test func `the socket is the user's alone`() throws {
        let server = server()
        try server.start()
        defer { server.stop() }

        var info = stat()
        #expect(lstat(socket.path, &info) == 0)
        #expect(info.st_mode & S_IFMT == S_IFSOCK)
        #expect(info.st_mode & 0o777 == 0o600)
    }

    @Test func `a stale socket is replaced`() async throws {
        try SocketClient.leaveStaleSocket(at: socket)
        let server = server()
        try server.start()
        defer { server.stop() }

        let answer = try await SocketClient.exchange(socket, "livepaper://settings\n")

        #expect(try CommandReply(line: answer) == .done(message: nil))
    }

    @Test func `a file that is not a socket is left alone`() throws {
        try Data("kept".utf8).write(to: socket)
        let server = server()

        #expect(throws: CommandServerError.notASocket(socket)) { try server.start() }
        #expect(try Data(contentsOf: socket) == Data("kept".utf8))
    }

    @Test func `a socket another server answers on is not taken`() async throws {
        let first = server(reply: .done(message: "first"))
        try first.start()
        defer { first.stop() }
        let second = server(reply: .done(message: "second"))

        #expect(throws: CommandServerError.inUse(socket)) { try second.start() }
        #expect(try CommandReply(line: try await SocketClient.exchange(socket, "livepaper://mute\n")) == .done(message: "first"))
    }

    @Test func `stopping removes the socket, and no one answers`() async throws {
        let server = server()
        try server.start()
        server.stop()

        #expect(!FileManager.default.fileExists(atPath: socket.path))
        await #expect(throws: SocketClient.Failure.self) { try await SocketClient.exchange(socket, "livepaper://mute\n") }
    }

    @Test func `a path too long for an address does not start`() {
        let long = folder.url.appending(path: String(repeating: "a", count: 120), directoryHint: .notDirectory)
        let server = CommandServer(socket: long) { _ in .done(message: nil) }

        #expect(throws: CommandServerError.pathTooLong(long)) { try server.start() }
    }

    nonisolated static let kinds: [Row<CommandServerError, String>] = [
        Row(
            "a path too long",
            .pathTooLong(URL(filePath: "/Users/sam/Library/Application Support/Livepaper/command.sock")),
            "the path does not fit a socket address"
        ),
        Row("not a socket", .notASocket(URL(filePath: "/Users/sam/command.sock")), "something that is not a socket is there"),
        Row("in use", .inUse(URL(filePath: "/Users/sam/command.sock")), "another copy of Livepaper answers there"),
        Row("a system call", .system("bind", errno: EADDRINUSE), "bind failed, errno 48"),
    ]

    @Test(arguments: kinds)
    func `a server that does not start is logged by its kind, never the socket's path`(row: Row<CommandServerError, String>) {
        #expect(row.input.kind == row.expected)
        #expect(LogWords.kind(of: row.input) == row.expected)
    }
}

/// The commands the handler was given.
@MainActor
final class HandledCommands {
    var commands: [Command] = []
}

/// A folder short enough for a socket's path, under the temporary directory,
/// removed when the test lets go of it. `TemporaryFolder`'s names are too long.
final class SocketFolder: Sendable {
    let url: URL

    init() throws {
        let template = FileManager.default.temporaryDirectory.appending(path: "lp-XXXXXX").path
        var bytes = Array(template.utf8CString)
        guard mkdtemp(&bytes) != nil else { throw CocoaError(.fileWriteUnknown) }
        guard let path = String(bytes: bytes.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), encoding: .utf8) else {
            throw CocoaError(.fileWriteInapplicableStringEncoding)
        }
        url = URL(filePath: path, directoryHint: .isDirectory)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}

/// A client as the `livepaper` tool is one: connect, write, read to the end.
enum SocketClient {
    struct Failure: Error {
        let call: String
        let errno: Int32
    }

    static func exchange(_ socket: URL, _ line: String) async throws -> Data {
        try await exchange(socket, Data(line.utf8))
    }

    /// Writes the bytes, closes the writing end unless told not to, and reads
    /// until the server closes. On a thread of its own: the reads block, and
    /// blocking the cooperative pool, a thread a core, starved the other tests'
    /// clients on CI's virtual Mac (a prompt client waited 9 s).
    static func exchange(_ socket: URL, _ bytes: Data, closingWrites: Bool = true) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            Thread.detachNewThread {
                continuation.resume(with: Result { try blockingExchange(socket, bytes, closingWrites: closingWrites) })
            }
        }
    }

    private static func blockingExchange(_ socket: URL, _ bytes: Data, closingWrites: Bool) throws -> Data {
        let fd = try connected(to: socket)
        defer { close(fd) }
        try bytes.withUnsafeBytes { buffer in
            var sent = 0
            while sent < buffer.count {
                let count = write(fd, buffer.baseAddress! + sent, buffer.count - sent)
                guard count > 0 else { throw Failure(call: "write", errno: errno) }
                sent += count
            }
        }
        if closingWrites { shutdown(fd, SHUT_WR) }
        var answer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = read(fd, &chunk, chunk.count)
            guard count > 0 else { break }
            answer.append(contentsOf: chunk[..<count])
        }
        return answer
    }

    /// A socket file no one listens on, as a crashed app leaves it.
    static func leaveStaleSocket(at socket: URL) throws {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        defer { close(fd) }
        guard var address = SocketAddress.make(socket) else { throw Failure(call: "address", errno: 0) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0 else { throw Failure(call: "bind", errno: errno) }
    }

    private static func connected(to socket: URL) throws -> Int32 {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard var address = SocketAddress.make(socket) else { throw Failure(call: "address", errno: 0) }
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else {
            let error = errno
            close(fd)
            throw Failure(call: "connect", errno: error)
        }
        return fd
    }
}
