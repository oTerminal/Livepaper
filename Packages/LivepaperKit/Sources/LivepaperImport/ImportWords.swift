import Foundation
import LivepaperCore

// What the import list and its toasts say, in English only for v1.0. The
// toast names the file, so a reason speaks of it as "it".

/// What the import list says while an import is at this stage.
public func stageWords(_ stage: ImportStage) -> String {
    switch stage {
    case .fingerprint: "Checking"
    case .probe: "Reading"
    case .convert: "Converting"
    case .normalise: "Optimising"
    case .validate: "Checking the loop"
    case .prepare: "Preparing the scene"
    case .artefacts: "Making the poster"
    case .commit: "Finishing"
    }
}

/// Why an import failed, for its row and its toast, and whether Retry can
/// help: it can when the cause lies outside the file (a drive that went, a
/// full disk), and cannot when the same file would fail the same way again.
public func importFailureWords(_ error: any Error) -> (reason: String, canRetry: Bool) {
    switch error {
    case let error as ImportError: words(for: error)
    case let error as MediaError: words(for: error)
    case let error as FFmpegError: words(for: error)
    // A Wallpaper Engine item that changed after discovery read it, to lead out of its folder.
    case let error as WallpaperEngineProjectError: (skipWords(.wallpaperEngine(error)), false)
    case ArtefactError.noPicture: ("It has no picture to make a poster from", false)
    case ArtefactError.posterNotWritten: ("Its poster could not be written", true)
    case DiscoverError.notFound: ("It could not be found", true)
    case let error as CocoaError where [.fileNoSuchFile, .fileReadNoSuchFile].contains(error.code): ("It could not be found", true)
    case let error as CocoaError where error.code == .fileWriteOutOfSpace: ("There is not enough disk space", true)
    default: ("It could not be imported", true)
    }
}

/// Why a discovered source was skipped, for its toast. What a project says is
/// repeated back only when it helps the user find the file: an unknown type or
/// a path out of the folder is untrusted text, and says nothing useful.
public func skipWords(_ reason: SkipReason) -> String {
    switch reason {
    case .wallpaperEngine(.runsCode(let type)):
        let kind = type == "application" ? "an application" : "a web page"
        return "It is \(kind) for Wallpaper Engine, which runs code of its own; only video and scene items can be imported"
    case .wallpaperEngine(.unsupportedType): return "Only Wallpaper Engine video and scene items can be imported"
    case .wallpaperEngine(.malformed): return "Its Wallpaper Engine project cannot be read"
    case .wallpaperEngine(.noFile): return "Its Wallpaper Engine project names no file"
    case .wallpaperEngine(.escapesFolder): return "Its Wallpaper Engine project names a file outside its folder"
    case .missingFile(let file): return "Its Wallpaper Engine project names “\(file)”, which is not in its folder"
    case .noScenePackage(let file): return "Its Wallpaper Engine scene has no “\(file)” in its folder"
    }
}

/// What an import says in a plain toast. A cancel says nothing.
public struct ImportToast: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        /// Nothing new: the file is in the library, or on the list, already.
        case alreadyThere
        /// It was not imported, and the words say why.
        case notImported
    }

    public let kind: Kind
    public let words: String

    public init(kind: Kind, words: String) {
        self.kind = kind
        self.words = words
    }

    /// A source file the library already has: nothing was imported.
    public static func duplicate(of wallpaper: Wallpaper) -> ImportToast {
        ImportToast(kind: .alreadyThere, words: "Already in the library as “\(wallpaper.name)”")
    }

    /// A file dropped again while its row is still on the list. `name` is the candidate's.
    public static func alreadyListed(name: String) -> ImportToast {
        ImportToast(kind: .alreadyThere, words: "“\(name)” is already in the import list")
    }

    /// A source that discovery passed over, named as the user dropped it.
    public static func skipped(_ skipped: SkippedSource) -> ImportToast {
        ImportToast(kind: .notImported, words: "“\(skipped.url.lastPathComponent)” was not imported. \(skipWords(skipped.reason)).")
    }

    /// An import that failed, or a source that could not be searched. `name` is the candidate's.
    public static func failed(name: String, error: any Error) -> ImportToast {
        ImportToast(kind: .notImported, words: "“\(name)” was not imported. \(importFailureWords(error).reason).")
    }
}

private func words(for error: ImportError) -> (reason: String, canRetry: Bool) {
    switch error {
    case .rejected(.unrecognised): ("It is not a kind of file Livepaper can read", false)
    case .rejected(.noVideo): ("It has no picture to play", false)
    case .rejected(.noFrames): ("It has no frames to play", false)
    case .rejected(.protected): ("It is copy-protected", false)
    // The helper is looked for once, when the importer is made: Retry would meet the same importer.
    case .helperMissing: ("Its format needs the ffmpeg helper, which is missing", false)
    case .helperOutputUnreadable: ("The ffmpeg helper converted it, but Livepaper cannot read the result", false)
    case .loopSeam: ("It would not loop without a gap", false)
    case .scene(.notAPackage): ("Its Wallpaper Engine scene package cannot be read", false)
    case .scene: ("Its Wallpaper Engine scene cannot be read", false)
    case .sceneWithoutSize: ("Its Wallpaper Engine scene has no fixed size, which Livepaper needs to show it", false)
    }
}

private func words(for error: MediaError) -> (reason: String, canRetry: Bool) {
    switch error {
    case .noVideoTrack: ("It has no picture to play", false)
    case .readFailed: ("It could not be read", true)
    case .writeFailed: ("Its optimised copy could not be written", true)
    }
}

private func words(for error: FFmpegError) -> (reason: String, canRetry: Bool) {
    switch error {
    case .launchFailed: ("The ffmpeg helper could not be started", true)
    case .failed: ("The ffmpeg helper could not convert it", false)
    case .timeLimitExceeded: ("Converting it took too long", false)
    case .sizeLimitExceeded: ("It would be too large once converted", false)
    }
}
