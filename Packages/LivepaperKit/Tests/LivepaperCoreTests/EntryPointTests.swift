import Foundation
import Testing
import LivepaperCore

struct EntryPointTests {
    static let movie = URL(filePath: "/Users/sam/Movies/Ocean.mov")
    static let item = URL(filePath: "/Users/sam/Downloads/431960/", directoryHint: .isDirectory)
    static let next = URL(string: "livepaper://next")!
    static let pause = URL(string: "livepaper://pause?display=all")!
    static let ocean = WallpaperID.numbered(1)

    // MARK: What LaunchServices hands over

    static let handovers: [Row<[URL], LaunchServicesHandover>] = [
        Row("a link", [next], LaunchServicesHandover(links: [next], files: 0)),
        Row("links, in the order handed over", [pause, next], LaunchServicesHandover(links: [pause, next], files: 0)),
        Row("a file is left: importing is done in the app's window", [movie], LaunchServicesHandover(links: [], files: 1)),
        Row("and a Wallpaper Engine folder", [item], LaunchServicesHandover(links: [], files: 1)),
        Row("files beside a link leave the link", [movie, next, item], LaunchServicesHandover(links: [next], files: 2)),
        Row("nothing", [], LaunchServicesHandover(links: [], files: 0)),
    ]

    @Test(arguments: handovers)
    func `of what LaunchServices hands over, only the links go on`(row: Row<[URL], LaunchServicesHandover>) {
        #expect(LaunchServicesHandover(row.input) == row.expected)
    }

    // MARK: What each door takes

    @Test func `the scheme takes every verb but status`() throws {
        for verb in Command.Verb.allCases where verb != .status {
            let keys = verb == .set ? "?wallpaper=\(Self.ocean)" : ""
            let command = try Command(string: "livepaper://\(verb.rawValue)\(keys)")
            #expect(EntryPoint.urlScheme.accepts(command))
            #expect(try EntryPoint.urlScheme.command(from: command.url) == command)
        }
        #expect(!EntryPoint.urlScheme.accepts(.status))
        #expect(throws: CommandRejection.notThroughThisDoor(.status)) {
            try EntryPoint.urlScheme.command(from: Command.status.url)
        }
    }

    @Test func `the socket takes every verb`() throws {
        #expect(EntryPoint.commandSocket.accepts(.status))
        #expect(try EntryPoint.commandSocket.command(from: "livepaper://status") == .status)
        #expect(try EntryPoint.commandSocket.command(from: "livepaper://next") == .next(.all))
    }

    @Test func `a door still rejects what is not a command`() {
        #expect(throws: CommandRejection.notAUUID(key: "wallpaper", value: "../x")) {
            try EntryPoint.urlScheme.command(from: URL(string: "livepaper://set?wallpaper=../x")!)
        }
        #expect(throws: CommandRejection.notLivepaper) { try EntryPoint.commandSocket.command(from: "hello") }
    }

    @Test func `neither door imports`() {
        #expect(throws: CommandRejection.unknownVerb("import")) {
            try EntryPoint.urlScheme.command(from: URL(string: "livepaper://import?file=/Users/sam/Movies/Ocean.mov")!)
        }
        #expect(throws: CommandRejection.unknownVerb("import")) {
            try EntryPoint.commandSocket.command(from: "livepaper://import?file=/Users/sam/Movies/Ocean.mov&set=all")
        }
    }
}
