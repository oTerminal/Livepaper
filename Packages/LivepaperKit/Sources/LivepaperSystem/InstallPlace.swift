import AppKit
import Darwin
import LivepaperCore

extension InstallLocation {
    /// This copy of Livepaper: `Bundle.main`'s path, whether Gatekeeper
    /// translocated it, as `SecTranslocateIsTranslocatedURL` answers, and
    /// whether its volume can be written. Read before anything is registered.
    public static func current() -> InstallLocation {
        let bundle = Bundle.main.bundleURL
        let isReadOnly = (try? bundle.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly
        return InstallLocation(
            bundlePath: bundle.path,
            isTranslocated: Translocation.isTranslocated(bundle),
            // Unknown, it is taken as writable: Move then says what went wrong.
            isVolumeWritable: !(isReadOnly ?? false)
        )
    }
}

/// Gatekeeper's translocation, asked of Security. `SecTranslocateIsTranslocatedURL`
/// is exported by Security.framework but declared in no public header of the
/// macOS SDK, so it is looked up by name; nil when it is missing or fails, and
/// `installDecision` then reads the path.
enum Translocation {
    private typealias IsTranslocatedURL = @convention(c) (
        CFURL, UnsafeMutablePointer<Bool>, UnsafeMutablePointer<Unmanaged<CFError>?>?
    ) -> UInt8

    private static let security = "/System/Library/Frameworks/Security.framework/Security"

    static func isTranslocated(_ url: URL) -> Bool? {
        guard let handle = dlopen(security, RTLD_LAZY | RTLD_NOLOAD) ?? dlopen(security, RTLD_LAZY),
              let symbol = dlsym(handle, "SecTranslocateIsTranslocatedURL") else { return nil }
        let isTranslocatedURL = unsafeBitCast(symbol, to: IsTranslocatedURL.self)
        var isTranslocated = false
        var error: Unmanaged<CFError>?
        guard isTranslocatedURL(url as CFURL, &isTranslocated, &error) != 0 else {
            error?.release()
            return nil
        }
        return isTranslocated
    }
}

/// Why Livepaper could not be moved to `/Applications`, in words for the card.
public enum ApplicationsMoveError: Error, Equatable, Sendable {
    /// A Livepaper is open from the Applications folder, and is left alone.
    case openThere
    /// The Applications folder cannot be written by this user.
    case notPermitted
    case noSpace
    /// Anything else, by its kind (`LogWords`).
    case failed(kind: String)

    public var words: String {
        switch self {
        case .openThere: "A Livepaper in the Applications folder is open. Quit it, then try again."
        case .notPermitted:
            "Livepaper could not be moved: this account cannot change the Applications folder. Drag it there in the Finder instead."
        case .noSpace: "Livepaper could not be moved: there is not enough space on the disk. Make some room, then try again."
        case .failed: "Livepaper could not be moved to the Applications folder. Try again, or drag it there in the Finder."
        }
    }
}

/// Moving this copy of Livepaper to `/Applications`, and opening it there once
/// this process has exited. Nothing is ever deleted outright: a
/// Livepaper already in Applications goes to the Trash, and a copy made across
/// volumes leaves its original in the Trash too.
public enum ApplicationsMove {
    /// Where Move puts Livepaper, whatever this copy's bundle is called, so
    /// that a "Livepaper 2.app" from Downloads replaces Livepaper rather than
    /// sitting beside it.
    public static let destination = URL(filePath: "/Applications/Livepaper.app", directoryHint: .isDirectory)

    /// Moves `bundle` to `destination`, answering the new bundle.
    public static func move(_ bundle: URL, to destination: URL = destination) throws(ApplicationsMoveError) -> URL {
        let files = FileManager.default
        let target = destination.standardizedFileURL
        let isOpenThere = NSWorkspace.shared.runningApplications.contains {
            $0.bundleURL?.standardizedFileURL == target && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier
        }
        if isOpenThere { throw .openThere }
        do {
            if files.fileExists(atPath: target.path) {
                try files.trashItem(at: target, resultingItemURL: nil)
            }
            if try isSameVolume(bundle, target.deletingLastPathComponent()) {
                try files.moveItem(at: bundle, to: target)
            } else {
                try files.copyItem(at: bundle, to: target)
                try files.trashItem(at: bundle, resultingItemURL: nil)
            }
        } catch let error as CocoaError where [.fileWriteNoPermission, .fileWriteVolumeReadOnly].contains(error.code) {
            throw .notPermitted
        } catch let error as CocoaError where error.code == .fileWriteOutOfSpace {
            throw .noSpace
        } catch {
            throw .failed(kind: LogWords.kind(of: error))
        }
        return target
    }

    /// Opens `app` once this process has exited, giving up waiting after 10 s:
    /// a shell outlives the app, waits for its process to go and then asks
    /// LaunchServices to open the moved copy, so that two Livepapers never run.
    public static func relaunch(_ app: URL) throws {
        let wait = """
            i=0; while /bin/kill -0 "$1" 2>/dev/null && [ "$i" -lt 100 ]; do /bin/sleep 0.1; i=$((i + 1)); done; /usr/bin/open "$2"
            """
        let shell = Process()
        shell.executableURL = URL(filePath: "/bin/sh")
        shell.arguments = ["-c", wait, "livepaper-relaunch", String(ProcessInfo.processInfo.processIdentifier), app.path]
        try shell.run()
    }

    private static func isSameVolume(_ one: URL, _ other: URL) throws -> Bool {
        let key = URLResourceKey.volumeIdentifierKey
        let first = try one.resourceValues(forKeys: [key]).volumeIdentifier as? NSObject
        let second = try other.resourceValues(forKeys: [key]).volumeIdentifier as? NSObject
        return first != nil && first == second
    }
}
