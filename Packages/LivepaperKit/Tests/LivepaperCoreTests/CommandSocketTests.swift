import Foundation
import Testing
import LivepaperCore

struct CommandSocketTests {
    static let temporary = URL(filePath: "/var/folders/x1/abcdefgh/T", directoryHint: .isDirectory)

    /// A home whose library socket path is `bytes` long: "/Users/" and "/Library/Application Support/Livepaper/command.sock" are 58.
    static func home(socketPathBytes bytes: Int, first: String = "") -> URL {
        let name = first + String(repeating: "a", count: bytes - 58 - first.utf8.count)
        return URL(filePath: "/Users/\(name)", directoryHint: .isDirectory)
    }

    @Test func `an address holds 104 bytes of path, the NUL included`() {
        #expect(SocketAddress.pathCapacity == 104)
    }

    static let paths: [Row<URL, String>] = [
        Row(
            "a usual home keeps the socket in the library",
            URL(filePath: "/Users/sam", directoryHint: .isDirectory),
            "/Users/sam/Library/Application Support/Livepaper/command.sock"
        ),
        Row(
            "103 bytes and the NUL fit",
            home(socketPathBytes: 103),
            home(socketPathBytes: 103).path + "/Library/Application Support/Livepaper/command.sock"
        ),
        Row(
            "104 bytes do not, and the socket moves to the temporary folder",
            home(socketPathBytes: 104),
            "/var/folders/x1/abcdefgh/T/livepaper-command.sock"
        ),
        Row(
            "the path is measured as the file system spells it, an accent decomposed",
            home(socketPathBytes: 103, first: "\u{E9}"),
            "/var/folders/x1/abcdefgh/T/livepaper-command.sock"
        ),
    ]

    @Test(arguments: paths)
    func `the socket is in the library when its path fits an address`(row: Row<URL, String>) {
        let socket = LibraryLocation(home: row.input).commandSocket(fallback: Self.temporary)

        #expect(socket.path == row.expected)
        #expect(SocketAddress.fits(socket))
    }

    static let folders: [Row<URL, String>] = [
        Row(
            "a usual home's socket is in the library folder",
            URL(filePath: "/Users/sam", directoryHint: .isDirectory),
            "the library folder"
        ),
        Row("a long home's is in the temporary folder", home(socketPathBytes: 104), "the temporary folder"),
    ]

    @Test(arguments: folders)
    func `the log says which folder the socket is in, never its path`(row: Row<URL, String>) {
        let socket = LibraryLocation(home: row.input).commandSocket(fallback: Self.temporary)

        #expect(LibraryLocation.commandSocketFolder(of: socket) == row.expected)
    }

    @Test func `an address carries the path and its NUL`() throws {
        let address = try #require(SocketAddress.make(URL(filePath: "/tmp/lp/command.sock")))
        let path = withUnsafeBytes(of: address.sun_path) { String(bytes: $0.prefix { $0 != 0 }, encoding: .utf8) }

        #expect(address.sun_family == sa_family_t(AF_UNIX))
        #expect(path == "/tmp/lp/command.sock")
    }

    @Test func `a path too long makes no address`() {
        let tooLong = Self.home(socketPathBytes: 104).appending(path: "Library/Application Support/Livepaper/command.sock")

        #expect(SocketAddress.make(tooLong) == nil)
        #expect(SocketAddress.make(URL(filePath: "/" + String(repeating: "a", count: 102))) != nil)
        #expect(SocketAddress.make(URL(filePath: "/" + String(repeating: "a", count: 103))) == nil)
    }
}
