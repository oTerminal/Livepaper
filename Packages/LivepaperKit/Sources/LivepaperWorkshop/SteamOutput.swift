import Foundation

/// Which Steam Guard code steamcmd is asking for.
public enum SteamGuard: Equatable, Sendable {
    /// The code Steam sends to the account's email address.
    case email
    /// The code the Steam Mobile app shows.
    case authenticator
}

/// What a line of steamcmd's console output means, as far as Livepaper cares.
/// Steam's results are kept in its own words, for `WorkshopError` to read.
public enum SteamLine: Equatable, Sendable {
    /// `Steam>`: the console waits for a command.
    case console
    /// steamcmd checking or fetching an update of itself; `percent` is nil where it prints `[----]`.
    case updating(percent: Int?)
    /// It has a saved login for the account and signs in with it.
    case savedLogin
    /// It has no saved login for the account, and will ask for its password.
    case noSavedLogin
    case passwordPrompt
    case codePrompt(SteamGuard)
    /// Waiting for the sign-in to be approved in the Steam Mobile app.
    case awaitingApproval
    /// Signed in: the account's details have arrived.
    case signedIn
    /// Steam refused the sign-in; the words are Steam's (`Invalid Password`, `Rate Limit Exceeded`).
    case signInFailed(String)
    case downloading(WorkshopItemID)
    /// Where steamcmd put the item's files, and how many bytes they are.
    case downloaded(WorkshopItemID, folder: String, bytes: Int64)
    /// Steam's reason in its words (`File Not Found`, `Failure`).
    case downloadFailed(WorkshopItemID?, String)
    case other
}

/// Reads one line of steamcmd's output, from its console or from its log.
public func readSteamLine(_ raw: String) -> SteamLine {
    let line = normalised(raw)
    return wholeLines[line] ?? readUpdate(line) ?? readDownload(line) ?? readSignInFailure(line) ?? .other
}

/// The lines that are only ever themselves.
private let wholeLines: [String: SteamLine] = [
    "Steam>": .console,
    "Logging in using cached credentials.": .savedLogin,
    "Cached credentials not found.": .noSavedLogin,
    "password:": .passwordPrompt,
    "Steam Guard code:": .codePrompt(.email),
    "Two-factor code:": .codePrompt(.authenticator),
    "Waiting for confirmation...": .awaitingApproval,
    "Waiting for user info...OK": .signedIn,
]

/// `[ 45%] …`, or `[----] …` where it does not say how far.
private func readUpdate(_ line: String) -> SteamLine? {
    if let match = line.wholeMatch(of: /\[\s*(\d{1,3})%\].*/) {
        return .updating(percent: Int(match.1))
    }
    return line.hasPrefix("[----]") ? .updating(percent: nil) : nil
}

/// steamcmd's warnings share its terminal and can land on the same line as a
/// result (seen: "Downloading item … ...PosixFileOpen: …"), so a download's lines
/// are found anywhere in the line, and its results at the end of it.
private func readDownload(_ line: String) -> SteamLine? {
    if let match = line.firstMatch(of: /Success\. Downloaded item (\d+) to "(.*)" \((\d+) bytes\)$/),
       let item = WorkshopItemID(match.1), let bytes = Int64(match.3) {
        return .downloaded(item, folder: String(match.2), bytes: bytes)
    }
    if let match = line.firstMatch(of: /ERROR! Download item (\d+) failed \(([^()]+)\)\.?$/) {
        return .downloadFailed(WorkshopItemID(match.1), String(match.2))
    }
    if let match = line.firstMatch(of: /ERROR! Timeout downloading item (\d+)$/) {
        return .downloadFailed(WorkshopItemID(match.1), "Timeout")
    }
    return line.prefixMatch(of: /Downloading item (\d+) \.\.\./).flatMap { WorkshopItemID($0.1) }.map(SteamLine.downloading)
}

/// At the end of the line that started the sign-in, or on a line of its own.
private func readSignInFailure(_ line: String) -> SteamLine? {
    if let match = line.firstMatch(of: /ERROR \(([^()]+)\)$/) {
        return .signInFailed(String(match.1))
    }
    return line.wholeMatch(of: /(?:FAILED login with result code|Login Failure:) (.+)/).map { .signInFailed(String($0.1)) }
}

/// A terminal's colours and carriage returns, the time `console_log.txt` puts
/// in front of each line, and the space around it, taken off.
private func normalised(_ raw: String) -> String {
    var line = raw.replacing(/\x{1B}\[[0-9;?]*[ -\/]*[@-~]/, with: "")
    line.removeAll { $0 == "\r" }
    if let stamp = line.prefixMatch(of: /\[\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\] ?/) {
        line.removeSubrange(stamp.range)
    }
    return line.trimmingCharacters(in: .whitespaces)
}

/// steamcmd's output as it arrives from its terminal, read into lines.
///
/// A prompt (`Steam>`, `password:`, a Steam Guard code) ends without a line
/// ending, since steamcmd waits on the same line, so the open line is read too.
/// A prompt is read once and then dropped: the terminal does not echo what is
/// typed, so steamcmd's next words follow it on the same line. Waiting for the
/// Steam Mobile app is said as soon as the line opens, since it stays open
/// until the approval comes.
public struct SteamTranscript: Sendable {
    /// Enough to say what went wrong, and no more.
    public static let linesKept = 12

    /// The last complete lines, oldest first, without the prompts. Nothing typed is in them.
    public private(set) var lastLines: [String] = []
    private var open = Data()
    private var openReported = false

    public init() {}

    public mutating func read(_ data: Data) -> [SteamLine] {
        read(data) { _ in }
    }

    /// `read`, telling `lines` each complete line as it is kept.
    public mutating func read(_ data: Data, lines: (String) -> Void) -> [SteamLine] {
        open.append(data)
        var read: [SteamLine] = []
        while let end = open.firstIndex(of: UInt8(ascii: "\n")) {
            let line = Self.text(open[open.startIndex..<end])
            open = Data(open[open.index(after: end)...])
            // An open line already said waits for nothing more.
            let meaning = readSteamLine(line)
            if !(openReported && meaning == .awaitingApproval) { read.append(meaning) }
            openReported = false
            if let kept = keep(line) { lines(kept) }
        }
        guard !open.isEmpty, !openReported else { return read }
        let meaning = readSteamLine(Self.text(open))
        switch meaning {
        case .console, .passwordPrompt, .codePrompt:
            open = Data()
            read.append(meaning)
        case .awaitingApproval:
            openReported = true
            read.append(meaning)
        default:
            // A line this long without an ending is not a prompt; keep its end only.
            if open.count > 65_536 { open = Data(open.suffix(4_096)) }
        }
        return read
    }

    private mutating func keep(_ line: String) -> String? {
        let kept = normalised(line)
        guard !kept.isEmpty else { return nil }
        lastLines.append(kept)
        if lastLines.count > Self.linesKept { lastLines.removeFirst(lastLines.count - Self.linesKept) }
        return kept
    }

    /// UTF-8, or Latin-1 where a byte is not: a line is never lost to its encoding.
    private static func text(_ bytes: Data) -> String {
        String(bytes: bytes, encoding: .utf8) ?? String(bytes: bytes, encoding: .isoLatin1) ?? ""
    }
}
