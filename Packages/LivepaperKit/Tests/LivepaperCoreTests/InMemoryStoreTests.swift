import LivepaperCore
import LivepaperTestSupport
import Testing

struct InMemoryStoreTests {
    @Test func `the library store gives back what was saved, or what it started with`() throws {
        let start = try Library.of(.numbered(1))
        let store = InMemoryLibraryStore(start)
        let first = try store.load()

        try store.save(try start.inserting(.numbered(2)))

        #expect(first == start)
        #expect(try store.load() == Library.of(.numbered(1), .numbered(2)))
        #expect(store.saveCount == 1)
    }

    @Test func `the app state store starts missing, and loads what was saved`() throws {
        let store = InMemoryAppStateStore()
        let first = store.load()
        var muted = AppState()
        muted.isMuted = true

        try store.save(muted)

        #expect(first == .missing)
        #expect(store.load() == .loaded(muted))
        #expect(store.saved == muted)
    }
}
