import Foundation

extension LibraryLocation {
    /// Where the command socket is: `commandSocket`, in the library, when its
    /// path fits a socket address, else a file in `temporaryFolder`, which the
    /// app and the tool both pass as the user's own temporary folder. A home
    /// with a long name is what moves it.
    public func commandSocket(fallback temporaryFolder: URL) -> URL {
        guard !SocketAddress.fits(commandSocket) else { return commandSocket }
        return temporaryFolder.appending(path: Self.temporarySocketName, directoryHint: .notDirectory)
    }

    static let temporarySocketName = "livepaper-command.sock"

    /// Which folder a socket `commandSocket(fallback:)` gave is in, in words a
    /// log line may hold: never its path, which names the user.
    public static func commandSocketFolder(of socket: URL) -> String {
        socket.lastPathComponent == temporarySocketName ? "the temporary folder" : "the library folder"
    }
}

/// A Unix-domain socket's address, whose `sun_path` holds the path and its NUL
/// in 104 bytes on macOS. The path is measured as the file system spells it,
/// accents decomposed, since that is what goes into the address.
public enum SocketAddress {
    public static let pathCapacity = MemoryLayout.size(ofValue: sockaddr_un().sun_path)

    public static func fits(_ path: URL) -> Bool {
        make(path) != nil
    }

    /// The address to bind or connect to, or nil when the path does not fit.
    public static func make(_ path: URL) -> sockaddr_un? {
        let bytes = path.withUnsafeFileSystemRepresentation { representation in
            representation.map { Array(UnsafeBufferPointer(start: $0, count: strlen($0))) }
        }
        guard let bytes, bytes.count < pathCapacity else { return nil }
        var address = sockaddr_un()
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        address.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            buffer.copyBytes(from: bytes.map(UInt8.init(bitPattern:)))
        }
        return address
    }
}
