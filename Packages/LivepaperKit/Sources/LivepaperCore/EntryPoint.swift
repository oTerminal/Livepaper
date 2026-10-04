import Foundation

/// A way a command reaches the app from outside its windows. Each turns
/// what it is handed into a `Command`, which the app model runs like any other.
/// Neither imports: importing is done in the app's window alone.
public enum EntryPoint: Hashable, Sendable, CaseIterable {
    /// A `livepaper://` URL LaunchServices handed over: anything can open one, a web page included.
    case urlScheme
    /// A request line on the command socket, from the `livepaper` tool.
    case commandSocket

    /// Whether this door takes the command. `status` answers with JSON, which
    /// only the socket can carry back.
    public func accepts(_ command: Command) -> Bool {
        switch self {
        case .urlScheme: command != .status
        case .commandSocket: true
        }
    }

    /// The command a URL handed to this door asks for, or why there is none.
    public func command(from url: URL) throws(CommandRejection) -> Command {
        try accepted(Command(url: url))
    }

    /// The command a request line asks for, or why there is none.
    public func command(from line: String) throws(CommandRejection) -> Command {
        try accepted(Command(string: line))
    }

    private func accepted(_ command: Command) throws(CommandRejection) -> Command {
        guard accepts(command) else { throw .notThroughThisDoor(command.verb) }
        return command
    }
}

/// What LaunchServices hands the app (`application(_:open:)`): the
/// `livepaper://` links, which `EntryPoint.urlScheme` parses, and the files,
/// which are left, since importing is done in the app's window alone. The app
/// declares no document types, so neither Open With nor the Dock offers it a
/// file, but one can still come, from `open -a Livepaper <file>`.
public struct LaunchServicesHandover: Hashable, Sendable {
    /// In the order they were handed over.
    public var links: [URL]
    /// Counted, never named: a log line holds no path.
    public var files: Int

    public init(links: [URL], files: Int) {
        self.links = links
        self.files = files
    }

    public init(_ urls: [URL]) {
        self.init(links: urls.filter { !$0.isFileURL }, files: urls.count(where: \.isFileURL))
    }
}
