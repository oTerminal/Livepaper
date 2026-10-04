import LivepaperCore
import Synchronization

/// A library store that keeps the library in memory, for tests and the fakes run.
public final class InMemoryLibraryStore: LibraryStore {
    private struct State {
        var library: Library
        var saveCount = 0
    }

    private let state: Mutex<State>

    public init(_ library: Library = Library()) {
        state = Mutex(State(library: library))
    }

    public func load() throws -> Library {
        state.withLock(\.library)
    }

    public func save(_ library: Library) throws {
        state.withLock { state in
            state.library = library
            state.saveCount += 1
        }
    }

    public var saveCount: Int { state.withLock(\.saveCount) }
}

/// An app state store that keeps the state in memory, for tests and the fakes run.
public final class InMemoryAppStateStore: AppStateStore {
    private struct State {
        var loadedFirst: AppStateLoad
        var saved: AppState?
    }

    private let state: Mutex<State>

    /// `load` answers `first` until something is saved.
    public init(_ first: AppStateLoad = .missing) {
        state = Mutex(State(loadedFirst: first))
    }

    public func load() -> AppStateLoad {
        state.withLock { $0.saved.map(AppStateLoad.loaded) ?? $0.loadedFirst }
    }

    public func save(_ appState: AppState) throws {
        state.withLock { $0.saved = appState }
    }

    /// The last state saved.
    public var saved: AppState? { state.withLock(\.saved) }
}
