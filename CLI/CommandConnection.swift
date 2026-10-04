import Foundation
import LivepaperCore

/// One exchange on the app's command socket: connect, write the command's
/// URL as a line, read the reply's line until the app closes.
enum CommandConnection {
    enum Failure: Error {
        /// No one is listening: the socket is absent, or refuses.
        case unreachable
        /// The app took the command and closed without a reply it could read.
        case noReply
    }

    static func send(_ command: Command, to socket: URL) throws(Failure) -> CommandReply {
        guard let address = SocketAddress.make(socket) else { throw .unreachable }
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw .unreachable }
        defer { close(fd) }
        var on: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))

        var socketAddress = address
        let connected = withUnsafePointer(to: &socketAddress) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard connected == 0 else { throw .unreachable }

        let request = Array((command.url.absoluteString + "\n").utf8)
        var sent = 0
        while sent < request.count {
            let count = request[sent...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { throw .noReply }
            sent += count
        }

        // No time limit of its own: the app answers every command, the diagnostics after a second or two.
        var reply = Data()
        var chunk = [UInt8](repeating: 0, count: 64 * 1024)
        while true {
            let count = read(fd, &chunk, chunk.count)
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { break }
            reply.append(contentsOf: chunk[..<count])
        }
        guard let answer = try? CommandReply(line: reply) else { throw .noReply }
        return answer
    }
}
