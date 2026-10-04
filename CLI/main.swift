import AppKit
import Foundation
import LivepaperCore

// The `livepaper` tool. Its arguments become a request
// (`CommandLineRequest`), whose command's `livepaper://` URL goes as one line
// over the app's command socket; the app runs it as it runs every door's
// commands and answers one line of JSON, which is printed: `status` readably
// or with `--json` as the report, `diagnostics` as it is, a refusal on standard
// error. `set <name>` asks for `status` first and resolves the name against it.
// The tool reads and writes no library file, so the app stays the only writer.
// There is no `import`: wallpapers are imported in the app's window alone.
//
// It uses the socket, not the URL scheme: LaunchServices reports only that the
// app took a URL, so there would be no reply and no exit code, and an XPC Mach
// service needs a launchd job the app lacks. When no one answers on the socket
// it opens the Livepaper it ships inside (else, run from outside an app, the
// one LaunchServices names for the bundle identifier), without bringing it
// forward, and tries again for a while; with LIVEPAPER_NO_LAUNCH set it leaves
// it closed.
// Exit status: 0 done, 1 refused, 2 usage, 3 unreachable (`CommandLineExit`).
//
// It ships inside the app, at Livepaper.app/Contents/Helpers/livepaper (in
// Contents/MacOS it would collide with the app's `Livepaper` on a
// case-insensitive disk), signed as app.livepaper.cli before the app is sealed.

/// The app on the other end of the socket, opened once at most in a run.
struct App {
    /// How long the app has to start answering once it has been opened.
    static let launchWait: Duration = .seconds(20)
    static let bundleIdentifier = "app.livepaper.Livepaper"

    /// The Livepaper this tool ships inside, through any link to the tool; nil
    /// when it runs from anywhere else.
    static var ownApp: URL? {
        guard let tool = Bundle.main.executableURL?.resolvingSymlinksInPath(), let app = enclosingApp(ofTool: tool),
              Bundle(url: app)?.bundleIdentifier == bundleIdentifier else { return nil }
        return app
    }

    /// Found as the app finds it.
    let socket = LibraryLocation(home: .homeDirectory).commandSocket(fallback: .temporaryDirectory)
    private var opened = false

    /// The app's reply to the command. When no one answers, the app is opened
    /// and asked again until it answers or `launchWait` is up.
    mutating func reply(to command: Command) -> CommandReply {
        let clock = ContinuousClock()
        var deadline: ContinuousClock.Instant?
        while true {
            do throws(CommandConnection.Failure) {
                return try CommandConnection.send(command, to: socket)
            } catch {
                guard error == .unreachable else { unreachable("Livepaper closed the connection without answering") }
                if deadline == nil {
                    open()
                    deadline = clock.now + Self.launchWait
                }
                if let deadline, clock.now >= deadline {
                    unreachable("Livepaper did not answer within \(Self.launchWait.components.seconds) seconds")
                }
                Thread.sleep(forTimeInterval: 0.25)
            }
        }
    }

    private mutating func open() {
        guard !opened else { return }
        opened = true
        guard ProcessInfo.processInfo.environment["LIVEPAPER_NO_LAUNCH"] == nil else { unreachable("Livepaper is not running") }
        guard let app = Self.ownApp ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.bundleIdentifier) else {
            unreachable("Livepaper is not running, and it could not be found to open")
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.openApplication(at: app, configuration: configuration) { _, error in
            if let error { unreachable("Livepaper could not be opened: \(error.localizedDescription)") }
        }
    }
}

func write(_ text: String, to handle: FileHandle) {
    guard !text.isEmpty else { return }
    handle.write(Data(text.utf8))
}

func finish(_ output: CommandLineOutput) -> Never {
    write(output.standardOutput, to: .standardOutput)
    write(output.standardError, to: .standardError)
    exit(output.exit.rawValue)
}

func unreachable(_ reason: String) -> Never {
    write("livepaper: \(reason)\n", to: .standardError)
    exit(CommandLineExit.unreachable.rawValue)
}

// A write to an app that has gone fails, rather than ending the tool without a word.
signal(SIGPIPE, SIG_IGN)

let request: CommandLineRequest
do throws(CommandLineUsageError) {
    request = try CommandLineRequest(arguments: Array(CommandLine.arguments.dropFirst()))
} catch {
    write("livepaper: \(error.message)\n\n\(CommandLineRequest.usage)\n", to: .standardError)
    exit(CommandLineExit.usage.rawValue)
}

var app = App()
switch request {
case .help:
    finish(CommandLineOutput(standardOutput: CommandLineRequest.usage + "\n", standardError: "", exit: .done))
case .status(let json):
    finish(CommandLineOutput(app.reply(to: .status), json: json))
case .send(let command):
    finish(CommandLineOutput(app.reply(to: command), json: false))
case .set(let name, let target):
    let answer = app.reply(to: .status)
    guard case .status(let report) = answer else {
        if case .refused = answer { finish(CommandLineOutput(answer, json: false)) }
        finish(CommandLineOutput(refusal: "Livepaper did not answer with its status"))
    }
    do throws(AssignmentNameError) {
        let assignment = try report.assignment(named: name)
        finish(CommandLineOutput(app.reply(to: .set(assignment, on: target)), json: false))
    } catch {
        finish(CommandLineOutput(refusal: error.reason))
    }
}
