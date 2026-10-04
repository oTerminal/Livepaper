import Foundation
import LivepaperImport

/// Why a Workshop item was not got: Steam's answer or steamcmd's trouble, or
/// a refusal the import would make anyway.
public enum WorkshopProblem: Equatable, Sendable {
    case steam(WorkshopError)
    case refused(WorkshopRefusal)

    public var words: String {
        switch self {
        case .steam(let error): workshopFailureWords(error).reason
        case .refused(let refusal): refusal.words
        }
    }

    /// Trying again as it is may work.
    public var canRetry: Bool {
        if case .steam(let error) = self { workshopFailureWords(error).canRetry } else { false }
    }

    /// Signing in is what would help.
    public var needsSignIn: Bool {
        if case .steam(let error) = self { workshopFailureWords(error).needsSignIn } else { false }
    }
}

/// The Workshop items the user asked for: one downloaded at a time, since two
/// steamcmds would both write Steam's folder, then handed to the import. A pure
/// reducer that answers effects for the app to carry out, as `ImportList` does.
///
/// A download that finds no saved login holds every item until the user signs
/// in (`askToSignIn`, then `signedIn`). A downloaded item is looked into
/// (`discover`) before it goes to the import, so that one discovery passes
/// over stays here with the import's own reason.
public struct WorkshopDownloads: Equatable, Sendable {
    public struct Row: Identifiable, Equatable, Sendable {
        public let item: WorkshopItemID
        /// The page's title, or the item's number.
        public var title: String
        public var state: State

        public var id: WorkshopItemID { item }
    }

    public enum State: Equatable, Sendable {
        case waiting
        /// steamcmd starting: checking for an update of itself.
        case starting
        /// steamcmd fetching an update of itself, `percent` done.
        case settingUp(percent: Int)
        case signingIn
        case downloading
        /// Downloaded; discovery is reading the folder.
        case opening
        case failed(WorkshopProblem)

        /// steamcmd is running for it, or its folder is being read.
        var isWorking: Bool {
            switch self {
            case .starting, .settingUp, .signingIn, .downloading, .opening: true
            case .waiting, .failed: false
            }
        }
    }

    public enum Effect: Equatable, Sendable {
        /// Run steamcmd for the item.
        case start(WorkshopItemID)
        /// Stop steamcmd, which is running for the item.
        case cancel(WorkshopItemID)
        /// Read the downloaded folder with `discoverSources` and tell `discovered`.
        case discover(WorkshopItemID, folder: URL)
        /// The folder goes to the import, which shows it from here on.
        case importFolder(URL)
        /// There is no saved login: show the sign-in, and tell `signedIn` when it worked.
        case askToSignIn
    }

    public private(set) var rows: [Row] = []
    /// The downloaded folders being read, by item.
    private var opening: [WorkshopItemID: URL] = [:]

    public init() {}

    /// The item the user asked for, with what its page said. One already on
    /// the list is left as it is, or tried again if it failed.
    public mutating func get(_ item: WorkshopItemID, title: String?, refusal: WorkshopRefusal? = nil) -> [Effect] {
        if let index = rows.firstIndex(where: { $0.item == item }) {
            guard case .failed = rows[index].state else { return [] }
            rows.remove(at: index)
        }
        let title = title.flatMap { $0.isEmpty ? nil : $0 } ?? "Workshop item \(item)"
        if let refusal {
            rows.append(Row(item: item, title: title, state: .failed(.refused(refusal))))
            return []
        }
        if isHeldForSignIn {
            rows.append(Row(item: item, title: title, state: .failed(.steam(.signInNeeded))))
            return [.askToSignIn]
        }
        rows.append(Row(item: item, title: title, state: .waiting))
        return startNext()
    }

    /// How steamcmd is getting on with the item.
    public mutating func progress(_ item: WorkshopItemID, _ progress: SteamProgress) {
        // Once downloaded, steamcmd has nothing more to say about it.
        guard let index = working(item), rows[index].state != .opening else { return }
        switch progress {
        case .updating(let percent?) where percent > 0:
            rows[index].state = .settingUp(percent: percent)
        case .updating:
            if case .settingUp = rows[index].state { return }
            rows[index].state = .starting
        case .signingIn, .waitingForApproval:
            rows[index].state = .signingIn
        case .downloading, .signingOut:
            rows[index].state = .downloading
        }
    }

    /// steamcmd put the item in `folder`.
    public mutating func downloaded(_ item: WorkshopItemID, folder: URL) -> [Effect] {
        guard let index = working(item) else { return [] }
        rows[index].state = .opening
        opening[item] = folder
        return [.discover(item, folder: folder)]
    }

    /// What discovery made of the downloaded folder.
    public mutating func discovered(_ item: WorkshopItemID, _ found: DiscoveredItem) -> [Effect] {
        guard let index = working(item), let folder = opening.removeValue(forKey: item) else { return [] }
        switch found {
        case .importable:
            rows.remove(at: index)
            return [.importFolder(folder)] + startNext()
        case .skipped(let reason):
            rows[index].state = .failed(.refused(.skipped(reason)))
        case .nothing:
            rows[index].state = .failed(.steam(.nothingToImport))
        }
        return startNext()
    }

    /// steamcmd could not get the item. With no saved login, every item waits for a sign-in.
    public mutating func failed(_ item: WorkshopItemID, _ error: WorkshopError) -> [Effect] {
        guard let index = working(item) else { return [] }
        opening[item] = nil
        rows[index].state = .failed(.steam(error))
        guard error == .signInNeeded else { return startNext() }
        for other in rows.indices where rows[other].state == .waiting {
            rows[other].state = .failed(.steam(.signInNeeded))
        }
        return [.askToSignIn]
    }

    /// A row's cancel: a running item's steamcmd is stopped; a waiting or failed one is taken off.
    public mutating func cancel(_ item: WorkshopItemID) -> [Effect] {
        guard let index = rows.firstIndex(where: { $0.item == item }) else { return [] }
        let wasWorking = rows[index].state.isWorking
        rows.remove(at: index)
        opening[item] = nil
        return wasWorking ? [.cancel(item)] + startNext() : []
    }

    /// A failed row waits again where it is. One held for sign-in asks for the sign-in instead.
    public mutating func retry(_ item: WorkshopItemID) -> [Effect] {
        guard let index = rows.firstIndex(where: { $0.item == item }), case .failed(let problem) = rows[index].state else { return [] }
        if problem.needsSignIn { return [.askToSignIn] }
        rows[index].state = .waiting
        return startNext()
    }

    /// The user signed in: every item held for it waits again.
    public mutating func signedIn() -> [Effect] {
        for index in rows.indices {
            if case .failed(let problem) = rows[index].state, problem.needsSignIn {
                rows[index].state = .waiting
            }
        }
        return startNext()
    }

    // MARK: Running

    private var isHeldForSignIn: Bool {
        rows.contains { if case .failed(let problem) = $0.state { problem.needsSignIn } else { false } }
    }

    private func working(_ item: WorkshopItemID) -> Int? {
        rows.firstIndex { $0.item == item && $0.state.isWorking }
    }

    private mutating func startNext() -> [Effect] {
        guard !rows.contains(where: \.state.isWorking), let next = rows.firstIndex(where: { $0.state == .waiting }) else { return [] }
        rows[next].state = .starting
        return [.start(rows[next].item)]
    }
}

/// What discovery found in a downloaded item's folder.
public enum DiscoveredItem: Equatable, Sendable {
    /// Something the import can take: it gets the folder.
    case importable
    /// An item discovery passes over, with its reason.
    case skipped(SkipReason)
    /// Neither: the folder holds nothing to import, or could not be read.
    case nothing

    public init(_ discovery: Discovery) {
        if !discovery.candidates.isEmpty {
            self = .importable
        } else if let skipped = discovery.skipped.first {
            self = .skipped(skipped.reason)
        } else {
            self = .nothing
        }
    }
}

/// What a row says while its item is being got: the detail under its title. Nil
/// while it waits, which the row says itself, and once it has failed.
public func workshopStageWords(_ state: WorkshopDownloads.State) -> String? {
    switch state {
    case .waiting, .failed: nil
    case .starting: "Starting Steam’s download tool"
    case .settingUp: "Updating Steam’s download tool"
    case .signingIn: "Signing in to Steam"
    case .downloading: "Downloading from Steam"
    case .opening: "Opening the item"
    }
}
