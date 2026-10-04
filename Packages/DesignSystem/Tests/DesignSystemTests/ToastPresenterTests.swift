import Testing
import DesignSystem

struct ToastPresenterTests {
    private let deleted = ToastItem(message: "Wallpaper deleted", undoTitle: "Undo")
    private let removed = ToastItem(message: "Removed from playlist", undoTitle: "Undo")
    private let imported = ToastItem(message: "3 wallpapers imported")

    @Test func `showing a toast presents it`() {
        var presenter = ToastPresenter()
        presenter.send(.show(deleted))

        #expect(presenter.current == deleted)
    }

    @Test func `a second toast replaces the first rather than queueing`() {
        var presenter = ToastPresenter()
        presenter.send(.show(deleted))
        presenter.send(.show(removed))
        #expect(presenter.current == removed)

        presenter.send(.expire(removed.id))
        #expect(presenter.current == nil)
    }

    @Test func `the replaced toast running out does not take the new one with it`() {
        var presenter = ToastPresenter()
        presenter.send(.show(deleted))
        presenter.send(.show(removed))
        presenter.send(.expire(deleted.id))

        #expect(presenter.current == removed)
    }

    @Test func `a toast left alone expires`() {
        var presenter = ToastPresenter()
        presenter.send(.show(imported))
        presenter.send(.expire(imported.id))

        #expect(presenter.current == nil)
    }

    @Test func `undo asks for the current toast's action and dismisses it`() {
        var presenter = ToastPresenter()
        presenter.send(.show(deleted))

        #expect(presenter.send(.undo) == .undo(deleted.id))
        #expect(presenter.current == nil)
    }

    @Test func `undo after a replacement undoes only the toast on screen`() {
        var presenter = ToastPresenter()
        presenter.send(.show(deleted))
        presenter.send(.show(removed))

        #expect(presenter.send(.undo) == .undo(removed.id))
    }

    @Test func `a toast without an undo action ignores undo`() {
        var presenter = ToastPresenter()
        presenter.send(.show(imported))

        #expect(presenter.send(.undo) == nil)
        #expect(presenter.current == imported)
    }

    @Test func `undo with nothing on screen does nothing`() {
        var presenter = ToastPresenter()

        #expect(presenter.send(.undo) == nil)
    }

    @Test func `dismissing hides the toast without undoing`() {
        var presenter = ToastPresenter()
        presenter.send(.show(deleted))

        #expect(presenter.send(.dismiss) == nil)
        #expect(presenter.current == nil)
    }
}
