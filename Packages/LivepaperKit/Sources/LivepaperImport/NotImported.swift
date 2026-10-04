import Foundation

/// A source that gave no wallpaper, and why, in the words the import list's
/// toasts use: skipped by discovery, not searched, failed or cancelled.
/// Onboarding's first card, which waits on its own import, says it so.
public struct NotImported: Hashable, Sendable {
    /// The source as it was handed over, or the candidate's name.
    public var name: String
    /// A sentence about "it", as the toasts say it.
    public var reason: String

    public init(name: String, reason: String) {
        self.name = name
        self.reason = reason
    }

    /// A URL that could not be searched, or an import that failed. `name` is the candidate's.
    public init(name: String, error: any Error) {
        self.init(name: name, reason: importFailureWords(error).reason)
    }

    /// A source discovery passed over, named as it was handed over.
    public static func skipped(_ skipped: SkippedSource) -> NotImported {
        NotImported(name: skipped.url.lastPathComponent, reason: skipWords(skipped.reason))
    }

    /// A row cancelled from the list, or by Quit, before it was done.
    public static func cancelled(name: String) -> NotImported {
        NotImported(name: name, reason: "Its import was cancelled")
    }

    /// What it came to in a sentence.
    public var line: String {
        "“\(name)” was not imported. \(reason)."
    }
}
