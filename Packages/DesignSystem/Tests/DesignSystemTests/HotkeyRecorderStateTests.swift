import Testing
import DesignSystem

struct HotkeyRecorderStateTests {
    private let next = Hotkey(keyCode: 45, modifiers: [.control, .option], keyLabel: "N")
    private let pause = Hotkey(keyCode: 35, modifiers: [.control, .option], keyLabel: "P")
    private let escape = Hotkey(keyCode: 53, modifiers: [], keyLabel: "⎋")
    private let delete = Hotkey(keyCode: 51, modifiers: [], keyLabel: "⌫")

    private func noConflicts(_: Hotkey) -> String? { nil }

    private func recording(from hotkey: Hotkey? = nil) -> HotkeyRecorderState {
        var state = HotkeyRecorderState(hotkey: hotkey)
        state.send(.begin, conflict: noConflicts)
        return state
    }

    @Test func `a recorder ships unassigned and idle`() {
        let state = HotkeyRecorderState()

        #expect(state.hotkey == nil)
        #expect(state.phase == .idle)
    }

    @Test func `a recorder can start in any phase`() {
        var state = HotkeyRecorderState(hotkey: pause, phase: .conflict(next, with: "Next wallpaper"))

        #expect(state.isRecording)
        #expect(state.phase == .conflict(next, with: "Next wallpaper"))
        #expect(state.send(.key(pause), conflict: noConflicts) == .changed(pause))
        #expect(state.phase == .idle)
    }

    @Test func `keys are ignored until recording begins`() {
        var state = HotkeyRecorderState()

        #expect(state.send(.key(next), conflict: noConflicts) == nil)
        #expect(state.hotkey == nil)
    }

    @Test func `recording a free combination assigns it`() {
        var state = recording()

        #expect(state.send(.key(next), conflict: noConflicts) == .changed(next))
        #expect(state.hotkey == next)
        #expect(state.phase == .idle)
    }

    @Test func `a key without a modifier is not a hotkey`() {
        var state = recording()
        let bare = Hotkey(keyCode: 45, modifiers: [], keyLabel: "N")
        let shifted = Hotkey(keyCode: 45, modifiers: [.shift], keyLabel: "N")

        #expect(state.send(.key(bare), conflict: noConflicts) == nil)
        #expect(state.send(.key(shifted), conflict: noConflicts) == nil)
        #expect(state.phase == .recording)
    }

    @Test func `a function key needs no modifier`() {
        var state = recording()
        let f5 = Hotkey(keyCode: 96, modifiers: [], keyLabel: "F5")

        #expect(state.send(.key(f5), conflict: noConflicts) == .changed(f5))
    }

    @Test func `a combination already in use is shown as a conflict and not assigned`() {
        var state = recording(from: pause)

        let effect = state.send(.key(next)) { _ in "Next wallpaper" }

        #expect(effect == nil)
        #expect(state.hotkey == pause)
        #expect(state.phase == .conflict(next, with: "Next wallpaper"))
    }

    @Test func `another combination can be tried straight after a conflict`() {
        var state = recording()
        state.send(.key(next)) { _ in "Next wallpaper" }

        #expect(state.send(.key(pause), conflict: noConflicts) == .changed(pause))
        #expect(state.phase == .idle)
    }

    @Test func `recording the combination it already has is not a conflict`() {
        var state = recording(from: next)

        state.send(.key(next)) { _ in "This recorder" }

        #expect(state.hotkey == next)
        #expect(state.phase == .idle)
    }

    @Test func `pressing Escape cancels and keeps the previous hotkey`() {
        var state = recording(from: pause)

        #expect(state.send(.key(escape), conflict: noConflicts) == nil)
        #expect(state.hotkey == pause)
        #expect(state.phase == .idle)
    }

    @Test func `pressing Escape cancels out of a conflict`() {
        var state = recording(from: pause)
        state.send(.key(next)) { _ in "Next wallpaper" }
        state.send(.key(escape), conflict: noConflicts)

        #expect(state.hotkey == pause)
        #expect(state.phase == .idle)
    }

    @Test func `pressing Delete clears the hotkey`() {
        var state = recording(from: pause)

        #expect(state.send(.key(delete), conflict: noConflicts) == .changed(nil))
        #expect(state.hotkey == nil)
        #expect(state.phase == .idle)
    }

    @Test func `pressing Delete with modifiers is an ordinary combination`() {
        var state = recording()
        let commandDelete = Hotkey(keyCode: 51, modifiers: [.command], keyLabel: "⌫")

        #expect(state.send(.key(commandDelete), conflict: noConflicts) == .changed(commandDelete))
    }

    @Test func `the clear button clears without recording first`() {
        var state = HotkeyRecorderState(hotkey: pause)

        #expect(state.send(.clear, conflict: noConflicts) == .changed(nil))
        #expect(state.hotkey == nil)
        #expect(state.phase == .idle)
    }

    @Test func `losing focus cancels recording`() {
        var state = recording(from: pause)
        state.send(.cancel, conflict: noConflicts)

        #expect(state.hotkey == pause)
        #expect(state.phase == .idle)
    }

    @Test func `modifiers are written in the system's order`() {
        let all = Hotkey(keyCode: 45, modifiers: [.command, .shift, .option, .control], keyLabel: "N")

        #expect(all.displayString == "⌃⌥⇧⌘N")
    }
}
