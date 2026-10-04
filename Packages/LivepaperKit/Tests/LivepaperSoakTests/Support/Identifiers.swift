import Foundation
import LivepaperCore
import LivepaperPlayback
import LivepaperSoak
import LivepaperSystem

// Readable, fixed identifiers: surface 1 is always the same surface.
private func numberedUUID(_ prefix: String, _ number: Int) -> UUID {
    let digits = String(number)
    let padded = String(repeating: "0", count: 12 - digits.count) + digits
    guard let uuid = UUID(uuidString: "\(prefix)-0000-0000-0000-\(padded)") else {
        preconditionFailure("not a UUID: \(prefix), \(number)")
    }
    return uuid
}

extension SurfaceID {
    static func numbered(_ number: Int) -> SurfaceID {
        SurfaceID(uuid: numberedUUID("CCCCCCCC", number))
    }
}

extension DisplayIdentity {
    static func numbered(_ number: Int) -> DisplayIdentity {
        DisplayIdentity(uuid: numberedUUID("DDDDDDDD", number))
    }
}

extension WallpaperID {
    static func numbered(_ number: Int) -> WallpaperID {
        WallpaperID(uuid: numberedUUID("AAAAAAAA", number))
    }
}

extension SurfaceWallpaper {
    /// Wallpaper `number`, for the decision lines, which name only the decision.
    static func numbered(_ number: Int) -> SurfaceWallpaper {
        let folder = URL(filePath: "/Users/tester/Library/Application Support/Livepaper/wallpapers/\(WallpaperID.numbered(number))")
        return SurfaceWallpaper(
            wallpaper: .numbered(number),
            video: folder.appending(path: "wallpaper.mov"),
            poster: folder.appending(path: "poster.heic"),
            presentation: Presentation(),
            volume: 0
        )
    }
}

/// The same identifiers as the log prints them.
enum Named {
    static func surface(_ number: Int) -> String { SurfaceID.numbered(number).description }
    static func display(_ number: Int) -> String { DisplayIdentity.numbered(number).description }
    static func wallpaper(_ number: Int) -> String { WallpaperID.numbered(number).description }
}

/// Lines as `log show` would give them, from the subsystem and category that log them.
enum Logged {
    static let extensionSubsystem = WallpaperExtensionIdentity.logSubsystem
    /// `LivepaperSystem.logSubsystem`, which is the main actor's: `ReadingTests` pins the two equal.
    static let appSubsystem = "app.livepaper.Livepaper"

    static func supervisor(_ message: String, at time: Date = .soakStart) -> LogLine {
        line(extensionSubsystem, "supervisor", message, time: time, process: "WallpaperExtension")
    }

    static func extensionLine(_ message: String, at time: Date = .soakStart) -> LogLine {
        line(extensionSubsystem, "extension", message, time: time, process: "WallpaperExtension")
    }

    static func surface(_ message: String, at time: Date = .soakStart) -> LogLine {
        line(extensionSubsystem, "surface", message, time: time, process: "WallpaperExtension")
    }

    static func bridge(_ message: String, at time: Date = .soakStart) -> LogLine {
        line(extensionSubsystem, "bridge", message, time: time, process: "WallpaperExtension")
    }

    static func host(_ message: String, at time: Date = .soakStart) -> LogLine {
        line(appSubsystem, HostLog.category, message, time: time, process: "Livepaper")
    }

    static func rotation(_ message: String, at time: Date = .soakStart) -> LogLine {
        line(appSubsystem, RotationLog.category, message, time: time, process: "Livepaper")
    }

    static func sensing(_ message: String, at time: Date = .soakStart) -> LogLine {
        line(appSubsystem, SensingLog.category, message, time: time, process: "Livepaper")
    }

    static func line(_ subsystem: String, _ category: String, _ message: String, time: Date, process: String) -> LogLine {
        LogLine(
            time: time, process: process, pid: process == "Livepaper" ? 500 : 711,
            subsystem: subsystem, category: category, message: message,
            text: "[\(subsystem):\(category)] \(message)"
        )
    }
}

extension Date {
    /// Fixed points in time. No test reads the clock.
    static let soakStart = Date(timeIntervalSince1970: 1_790_000_000)

    static func soak(_ seconds: TimeInterval) -> Date {
        soakStart.addingTimeInterval(seconds)
    }
}
