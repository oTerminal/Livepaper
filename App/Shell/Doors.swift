import AppKit
import LivepaperCore
import LivepaperSystem

/// The ways a command reaches the app from outside its windows:
/// `livepaper://` links, and the command socket the `livepaper` tool talks to.
/// Each turns what it is handed into one `Command` (`EntryPoint`), which the
/// model runs as the window's controls run the same actions. Neither imports:
/// importing is done in the app's window alone, and a file LaunchServices
/// hands over is left.
final class Doors {
    private let model: AppModel
    private let windows: AppWindows
    private let workshop: WorkshopModel
    private var server: CommandServer?

    init(model: AppModel, windows: AppWindows, workshop: WorkshopModel) {
        self.model = model
        self.windows = windows
        self.workshop = workshop
    }

    private var shell: CommandShell {
        CommandShell(
            openLibrary: { [windows] in windows.openLibrary() },
            openSettings: { [windows] in windows.openSettings() },
            steamAccount: { [workshop] in workshop.account }
        )
    }

    // MARK: LaunchServices

    /// `application(_:open:)`: `livepaper://` links. A file is logged by count
    /// and left, whether it came from `open -a` or anywhere else.
    func open(_ urls: [URL]) {
        let handover = LaunchServicesHandover(urls)
        if handover.files > 0 {
            AppLog.logger.notice("\(AppLog.filesLeft(handover.files), privacy: .public)")
        }
        for link in handover.links {
            open(link: link)
        }
    }

    /// Anything can open a link, a web page included: a rejection is logged and
    /// goes no further. What a link can ask is what the popover's buttons do.
    private func open(link: URL) {
        let command: Command
        do throws(CommandRejection) {
            command = try EntryPoint.urlScheme.command(from: link)
        } catch {
            AppLog.logger.error("\(AppLog.linkRefused(error), privacy: .public)")
            return
        }
        Task {
            let reply = await model.perform(command, from: .urlScheme, shell: shell)
            // A link's `diagnostics` has no one to answer, so its report goes on the clipboard.
            if case .diagnostics(let text) = reply {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                AppLog.logger.notice("\(AppLog.diagnosticsCopied, privacy: .public)")
            }
        }
    }

    // MARK: The command socket

    /// Opens the socket once the launch has read the library, for the `livepaper` tool.
    func openSocket(at socket: URL) {
        let server = CommandServer(socket: socket) { [weak self] command in
            guard let self else { return .refused(.quitting) }
            return await model.perform(command, from: .commandSocket, shell: shell)
        }
        Task {
            await model.untilReady()
            guard self.server == nil, !model.isQuitting else { return }
            do {
                try FileManager.default.createDirectory(at: socket.deletingLastPathComponent(), withIntermediateDirectories: true)
                try server.start()
                self.server = server
                AppLog.logger.notice("\(AppLog.socketOpened(at: socket), privacy: .public)")
            } catch {
                AppLog.logger.error("\(AppLog.socketNotOpened(error), privacy: .public)")
            }
        }
    }

    /// At quit: the socket file goes, and the tool finds no one there.
    func closeSocket() {
        guard let server else { return }
        server.stop()
        self.server = nil
        AppLog.logger.notice("\(AppLog.socketClosed, privacy: .public)")
    }

    // MARK: The fakes run

    /// A door driven from the fakes remote, where nothing can open a
    /// link on the fakes run alone, and the fakes open no socket:
    ///
    ///     door link livepaper://next | door socket livepaper://status
    ///
    /// `socket` runs the command as the socket would and logs its reply.
    /// Answers whether it was one of these.
    func performFake(_ rest: String) -> Bool {
        let words = rest.split(separator: " ", maxSplits: 1).map(String.init)
        guard let kind = words.first, words.count == 2 else { return false }
        let argument = words[1]
        switch kind {
        case "link":
            guard let link = URL(string: argument) else { return false }
            open(link: link)
        case "socket":
            Task {
                let command: Command
                do throws(CommandRejection) {
                    command = try EntryPoint.commandSocket.command(from: argument)
                } catch {
                    AppLog.logger.notice("fakes: socket refused \(error.kind, privacy: .public)")
                    return
                }
                let reply = await model.perform(command, from: .commandSocket, shell: shell)
                let line = (try? reply.line()).flatMap { String(bytes: $0, encoding: .utf8) } ?? "unreadable"
                AppLog.logger.notice("fakes: socket reply \(line, privacy: .public)")
            }
        default:
            return false
        }
        return true
    }
}
