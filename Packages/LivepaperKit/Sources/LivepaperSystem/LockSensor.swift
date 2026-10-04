import CoreGraphics
import Foundation

/// Whether the session's screen is locked.
public protocol LockSensor: AnyObject {
    /// Whether the screen is locked now, and again each time that changes.
    func updates() -> AsyncStream<Bool>
}

/// Listens for the lock and unlock notifications the system posts to every
/// process, and reads the session once at the start.
public final class SystemLockSensor: LockSensor {
    static let locked = "com.apple.screenIsLocked"
    static let unlocked = "com.apple.screenIsUnlocked"

    private let broadcast = Broadcast<Bool>()
    private let triggers = NotificationTriggers()

    public init() {
        broadcast.whenRead(start: { [weak self] in self?.start() }, stop: { [weak self] in self?.triggers.stop() })
    }

    public func updates() -> AsyncStream<Bool> {
        broadcast.stream()
    }

    private func start() {
        triggers.start([.distributed(Self.locked), .distributed(Self.unlocked)]) { [weak self] name in
            guard let self else { return }
            let locked = name.rawValue == Self.locked
            if locked != broadcast.latest { broadcast.send(locked) }
        }
        broadcast.send(Self.isLockedNow())
    }

    /// The session dictionary carries the key only while the screen is locked.
    private static func isLockedNow() -> Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return session?["CGSSessionScreenIsLocked"] as? Bool ?? false
    }
}
