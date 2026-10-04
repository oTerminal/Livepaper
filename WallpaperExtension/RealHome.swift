import Darwin
import Foundation
import LivepaperCore

/// The one place the extension works out where the library is.
/// Inside the sandbox `NSHomeDirectory()` and `URL.homeDirectory` give the
/// container, so the real home folder comes from the password database. Every
/// file the extension opens is then a `LibraryPath` resolved in this location.
enum RealHome {
    static func libraryLocation() -> LibraryLocation {
        LibraryLocation(home: folder())
    }

    private static func folder() -> URL {
        if let entry = getpwuid(getuid()), let directory = entry.pointee.pw_dir {
            return URL(filePath: String(cString: directory), directoryHint: .isDirectory)
        }
        // The container has no library in it: the render state reads as
        // missing and every surface shows the neutral colour, which the log explains.
        let container = URL.homeDirectory
        ExtensionLog.error(.noHome(fallback: container))
        return container
    }
}
