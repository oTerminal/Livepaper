import Foundation

/// Whether macOS has an extension registered. WallpaperAgent launches only what is, and the
/// store names the extension by identifier alone, so the store is written only after this says
/// yes. Injected, so that tests run nothing.
public protocol ExtensionListing: AnyObject {
    func isListed(_ bundleIdentifier: String) async -> Bool
}

/// Asks `pluginkit -m -i <identifier>`, which only lists: it registers, removes and elects nothing.
public final class PluginKit: ExtensionListing {
    public init() {}

    public func isListed(_ bundleIdentifier: String) async -> Bool {
        guard let output = await Self.run(["-m", "-i", bundleIdentifier]) else { return false }
        return Self.lists(bundleIdentifier, in: output)
    }

    /// Whether `pluginkit -m` output lists the extension, and the user has not turned it off.
    ///
    /// Each registered copy is a line: an election mark or a space (`+` chosen by the user, `-`
    /// turned off, `=` superseded by another copy, `!` debugging), the identifier, then the
    /// version in brackets, and more after a tab with `-v`. Nothing is printed when there is
    /// none, and pluginkit still exits 0. On the development Mac, 2026-09-24:
    /// `     app.livepaper.Livepaper.WallpaperExtension(0.1.0)`.
    nonisolated public static func lists(_ bundleIdentifier: String, in output: String) -> Bool {
        output.split(whereSeparator: \.isNewline).contains { line in
            var rest = line.drop { $0 == " " || $0 == "\t" }
            if let mark = rest.first, "+-=!".contains(mark) {
                guard mark != "-" else { return false }
                rest = rest.dropFirst().drop { $0 == " " || $0 == "\t" }
            }
            guard rest.hasPrefix(bundleIdentifier) else { return false }
            let next = rest.dropFirst(bundleIdentifier.count).first
            return next == nil || next == "(" || next == "\t" || next == " "
        }
    }

    /// How long pluginkit may take. It answers at once; a hang ends here, not in onboarding.
    nonisolated static let timeLimit: DispatchTimeInterval = .seconds(10)

    /// Runs pluginkit on a queue of its own, off the main actor, and gives its output: nil when
    /// it did not start, failed, or ran past the time limit.
    nonisolated private static func run(_ arguments: [String]) async -> String? {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: runWaiting(arguments))
            }
        }
    }

    /// Blocks until pluginkit exits. Its output is a line per registered copy, far less than a
    /// pipe holds, so it is read after the exit.
    nonisolated private static func runWaiting(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/pluginkit")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }
        guard exited.wait(timeout: .now() + timeLimit) == .success else {
            process.terminate()
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        return String(bytes: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
    }
}
