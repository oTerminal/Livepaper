import Foundation

/// An error that says what kind it is in words a log line may hold.
public protocol KindNamingError: Error {
    /// What went wrong, without a path, a user name or a file's name.
    var kind: String { get }
}

/// What a log line may say of things whose description can name the user.
///
/// Livepaper's log lines never hold a path, a user name or a source file's
/// name: the diagnostics carry the extension's lines, and a user may hand
/// the app's over too. An error's description is Foundation's to word, and
/// names the file it is about, so an error is logged by its kind.
public enum LogWords {
    /// The error's own kind when it names one; otherwise its domain and code,
    /// and the POSIX error under it: `NSCocoaErrorDomain 513, POSIX error 13`.
    public static func kind(of error: any Error) -> String {
        if let named = error as? any KindNamingError { return named.kind }
        let error = error as NSError
        var words = "\(error.domain) \(error.code)"
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError, underlying.domain == NSPOSIXErrorDomain {
            words += ", POSIX error \(underlying.code)"
        }
        return words
    }
}
