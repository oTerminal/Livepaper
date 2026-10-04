import AppKit
import LivepaperCore
import LivepaperSystem
import UniformTypeIdentifiers

// The diagnostics report: Settings' "Copy Diagnostics" and "Save…", a
// `livepaper://diagnostics` link, and `livepaper diagnostics` over the socket
// all give the same text. It is made here from what the model holds and what
// the services read (the wallpaper store's shape, the extension's log), and
// redacted of the home folder, the user's and the Steam account's names, and
// every wallpaper's and file's name. Nothing is sent anywhere.

extension AppModel {
    /// The report as it is now. Reading the extension's log takes a second or two.
    func diagnosticsReport(steamAccount: String?) async -> DiagnosticsReport {
        let log = await services.extensionLog()
        let userNames = [NSUserName(), NSFullUserName()] + [steamAccount].compactMap(\.self)
        // The files imported this session; the library's own files and every wallpaper's name the redaction adds.
        let sourceFileNames = importList.rows.map { $0.candidate.source.lastPathComponent }
        let redaction = Redaction(home: NSHomeDirectory(), userNames: userNames, library: library, sourceFileNames: sourceFileNames)
        let appex = Bundle.main.bundleURL.appending(path: "Contents/Extensions/WallpaperExtension.appex", directoryHint: .isDirectory)
        return DiagnosticsReport(
            madeAt: Date(),
            app: .main,
            wallpaperExtension: Bundle(url: appex).flatMap(BundleVersion.init(bundle:)),
            machine: .current(),
            isTranslocated: BundleIdentity.current().isTranslocated,
            host: hostStatus,
            state: state,
            connected: displays.map(\.identity),
            isPausedAll: isPausedAll,
            loginItem: systemServices.loginItem,
            loginItemIntent: state.loginItemIntent?.openAtLogin,
            store: services.storeShape(),
            extensionLog: log,
            redaction: redaction
        )
    }

    /// "Copy Diagnostics", and a `livepaper://diagnostics` link.
    func copyDiagnostics(steamAccount: String?) async {
        let report = await diagnosticsReport(steamAccount: steamAccount)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report.text, forType: .string)
        AppLog.logger.notice("\(AppLog.diagnosticsCopied, privacy: .public)")
    }

    /// "Save…": where to save a report, named by the time, as a sheet on the
    /// window in front (Settings); nil when the user cancels.
    func chooseDiagnosticsFile() async -> URL? {
        let panel = NSSavePanel()
        panel.title = "Save Diagnostics"
        panel.nameFieldStringValue = DiagnosticsReport.fileName(madeAt: Date())
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        let response: NSApplication.ModalResponse
        if let window = NSApp.keyWindow, window.attachedSheet == nil {
            response = await panel.beginSheetModal(for: window)
        } else {
            NSApp.activate()
            response = await panel.begin()
        }
        return response == .OK ? panel.url : nil
    }

    /// Writes a report to `file`, replacing what is there, as the Save panel asked.
    func saveDiagnostics(to file: URL, steamAccount: String?) async throws {
        let report = await diagnosticsReport(steamAccount: steamAccount)
        do {
            try Data(report.text.utf8).write(to: file, options: .atomic)
            AppLog.logger.notice("\(AppLog.diagnosticsSaved, privacy: .public)")
        } catch {
            AppLog.logger.error("\(AppLog.diagnosticsNotSaved(error), privacy: .public)")
            throw error
        }
    }
}
