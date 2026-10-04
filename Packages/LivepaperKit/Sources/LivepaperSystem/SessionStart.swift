import Darwin
import Foundation

/// One entry of the login records (utmpx), as far as the session's start needs it.
nonisolated public struct LoginRecord: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case boot
        /// A login that is still running.
        case userProcess
        /// A login that has ended.
        case deadProcess
        case other
    }

    public var kind: Kind
    /// The short name.
    public var user: String
    /// `console` for the login at the Mac's own screen, `ttys000` and so on for a terminal's.
    public var line: String
    public var time: Date

    public init(kind: Kind, user: String, line: String, time: Date) {
        self.kind = kind
        self.user = user
        self.line = line
        self.time = time
    }
}

/// When the user's login session started: what the rotation driver's `.login`
/// is measured against. A display whose last rotation is older rotates once
/// at launch; a relaunch in the same session finds it newer and does not.
///
/// The login at the console, from the login records (`getutxent`, a running
/// `USER_PROCESS` on line `console` for the user running the app), and the
/// Mac's boot time (`kern.boottime`) when there is none. On macOS 27.0 the
/// console login answered, 33 s after the boot; a logout and a login without a
/// restart only the login records see. Reading either needs no permission.
nonisolated public struct SessionStart: Equatable, Sendable {
    public enum Source: Equatable, Sendable {
        case consoleLogin
        case boot
    }

    public var date: Date
    public var source: Source

    public init(date: Date, source: Source) {
        self.date = date
        self.source = source
    }

    /// This session's start, or nil when neither the login records nor the boot time can be read.
    public static func current() -> SessionStart? {
        if let user = currentUser, let login = consoleLogin(of: user, in: loginRecords()) {
            return SessionStart(date: login, source: .consoleLogin)
        }
        return bootTime().map { SessionStart(date: $0, source: .boot) }
    }

    /// The latest running console login of `user`: after a logout and a login
    /// without a restart, the one before has ended, or is older.
    public static func consoleLogin(of user: String, in records: [LoginRecord]) -> Date? {
        records.filter { $0.kind == .userProcess && $0.line == "console" && $0.user == user }.map(\.time).max()
    }

    // MARK: Reading the system

    private static var currentUser: String? {
        guard let entry = getpwuid(getuid()) else { return nil }
        return String(cString: entry.pointee.pw_name)
    }

    /// Every entry of the login records. `getutxent` walks a process-wide
    /// cursor, so the walk is not made from two threads at once.
    private static func loginRecords() -> [LoginRecord] {
        recordsLock.lock()
        defer { recordsLock.unlock() }
        setutxent()
        defer { endutxent() }
        var records: [LoginRecord] = []
        while let entry = getutxent() {
            var utmp = entry.pointee
            records.append(LoginRecord(
                kind: kind(of: utmp.ut_type),
                user: text(&utmp.ut_user),
                line: text(&utmp.ut_line),
                time: Date(timeIntervalSince1970: TimeInterval(utmp.ut_tv.tv_sec) + TimeInterval(utmp.ut_tv.tv_usec) / 1_000_000)
            ))
        }
        return records
    }

    private static let recordsLock = NSLock()

    private static func kind(of type: Int16) -> LoginRecord.Kind {
        switch Int32(type) {
        case BOOT_TIME: .boot
        case USER_PROCESS: .userProcess
        case DEAD_PROCESS: .deadProcess
        default: .other
        }
    }

    /// A fixed-size C string field, up to its first zero byte.
    private static func text<Field>(_ field: inout Field) -> String {
        withUnsafeBytes(of: &field) { String(bytes: $0.prefix { $0 != 0 }, encoding: .utf8) ?? "" }
    }

    private static func bootTime() -> Date? {
        var time = timeval()
        var size = MemoryLayout<timeval>.size
        var name: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&name, 2, &time, &size, nil, 0) == 0, time.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_usec) / 1_000_000)
    }
}
