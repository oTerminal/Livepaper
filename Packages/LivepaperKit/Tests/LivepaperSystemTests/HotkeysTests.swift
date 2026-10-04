import Carbon.HIToolbox
import CoreGraphics
import Foundation
import LivepaperCore
import LivepaperSystem
import os
import Testing

/// Answers as Carbon does, without it: what macOS or another app holds
/// exclusively is taken, and so is a combination this process already holds
/// under another identifier.
@MainActor
final class FakeHotkeyRegistrar: HotkeyRegistrar {
    var onPress: ((UInt32) -> Void)?
    /// Combinations another process holds.
    var heldElsewhere: [KeyCombination] = []
    /// Combinations whose registration fails with a status that says nothing about who has them.
    var failing: [KeyCombination] = []
    private(set) var held: [UInt32: KeyCombination] = [:]
    /// Every registration asked for, trials included.
    private(set) var requests: [KeyCombination] = []

    func register(_ combination: KeyCombination, id: UInt32) -> HotkeyRegistration {
        requests.append(combination)
        if failing.contains(where: { $0.sameKeys(as: combination) }) { return .failed(OSStatus(paramErr)) }
        let holders = heldElsewhere + held.filter { $0.key != id }.map(\.value)
        if holders.contains(where: { $0.sameKeys(as: combination) }) { return .taken }
        held[id] = combination
        return .registered
    }

    func unregister(id: UInt32) {
        held[id] = nil
    }

    /// The user pressing the keys: whatever holds them hears it.
    func press(_ combination: KeyCombination) {
        for (id, holding) in held where holding.sameKeys(as: combination) {
            onPress?(id)
        }
    }

    var heldCombinations: Set<KeyCombination> {
        Set(held.values)
    }
}

extension KeyCombination {
    func sameKeys(as other: KeyCombination) -> Bool {
        keyCode == other.keyCode && modifiers == other.modifiers
    }
}

@MainActor
struct HotkeysTests {
    nonisolated static let controlOptionP = KeyCombination(keyCode: 35, modifiers: [.control, .option], keyLabel: "P")
    nonisolated static let controlOptionN = KeyCombination(keyCode: 45, modifiers: [.control, .option], keyLabel: "N")
    nonisolated static let controlOptionM = KeyCombination(keyCode: 46, modifiers: [.control, .option], keyLabel: "M")

    let registrar = FakeHotkeyRegistrar()
    let changes = Recorded<[HotkeyAction: KeyCombination]>()
    let presses = Recorded<HotkeyAction>()

    func hotkeys(_ combinations: [HotkeyAction: KeyCombination] = [:]) -> Hotkeys {
        Hotkeys(
            combinations: combinations,
            registrar: registrar,
            logger: Logger(subsystem: "app.livepaper.tests", category: Hotkeys.logCategory),
            onChange: changes.append,
            onPress: presses.append
        )
    }

    // MARK: Launch and presses

    @Test func `a launch registers each combination the state has`() {
        let hotkeys = hotkeys([.nextWallpaper: Self.controlOptionN, .mute: Self.controlOptionM])

        #expect(hotkeys.combinations == [.nextWallpaper: Self.controlOptionN, .mute: Self.controlOptionM])
        #expect(registrar.heldCombinations == [Self.controlOptionN, Self.controlOptionM])
        #expect(changes.values.isEmpty)
    }

    @Test func `a press runs the action that has the combination`() {
        withExtendedLifetime(hotkeys([.nextWallpaper: Self.controlOptionN, .mute: Self.controlOptionM])) {
            registrar.press(Self.controlOptionN)
            registrar.press(Self.controlOptionP)
            registrar.press(Self.controlOptionM)
        }

        #expect(presses.values == [.nextWallpaper, .mute])
    }

    @Test func `a combination held elsewhere at launch stays assigned, and a press there does nothing here`() {
        registrar.heldElsewhere = [Self.controlOptionN]

        let hotkeys = hotkeys([.nextWallpaper: Self.controlOptionN])
        registrar.press(Self.controlOptionN)

        #expect(hotkeys.combinations == [.nextWallpaper: Self.controlOptionN])
        #expect(registrar.held.isEmpty)
        #expect(presses.values.isEmpty)
    }

    // MARK: Availability

    @Test func `a combination nothing has is free, and the trial registration is released`() {
        let hotkeys = hotkeys()

        #expect(hotkeys.availability(of: Self.controlOptionP, for: .pauseOrResumeAll) == .free)
        #expect(registrar.requests == [Self.controlOptionP])
        #expect(registrar.held.isEmpty)
    }

    @Test func `another action's combination is used by it, by name, without asking macOS`() {
        let hotkeys = hotkeys([.nextWallpaper: Self.controlOptionN])
        // The layout can print the key differently; the key and its modifiers are what count.
        let sameKeys = KeyCombination(keyCode: 45, modifiers: [.option, .control], keyLabel: "n")

        let availability = hotkeys.availability(of: sameKeys, for: .mute)

        #expect(availability == .usedBy(.nextWallpaper))
        #expect(availability.owner == "Next Wallpaper")
        #expect(registrar.requests == [Self.controlOptionN])
    }

    @Test func `a combination macOS says another process holds is taken elsewhere`() {
        registrar.heldElsewhere = [Self.controlOptionP]
        let hotkeys = hotkeys()

        #expect(hotkeys.availability(of: Self.controlOptionP, for: .pauseOrResumeAll) == .takenElsewhere)
    }

    @Test func `an action's own combination, held already, is free`() {
        let hotkeys = hotkeys([.nextWallpaper: Self.controlOptionN])

        #expect(hotkeys.availability(of: Self.controlOptionN, for: .nextWallpaper) == .free)
        #expect(registrar.heldCombinations == [Self.controlOptionN])
    }

    @Test func `an action's own combination that another process took is taken elsewhere`() {
        registrar.heldElsewhere = [Self.controlOptionN]
        let hotkeys = hotkeys([.nextWallpaper: Self.controlOptionN])

        #expect(hotkeys.availability(of: Self.controlOptionN, for: .nextWallpaper) == .takenElsewhere)
    }

    @Test func `a registration that fails for another reason claims nothing, so the combination is free`() {
        registrar.failing = [Self.controlOptionP]
        let hotkeys = hotkeys()

        #expect(hotkeys.availability(of: Self.controlOptionP, for: .mute) == .free)
    }

    // MARK: Assigning

    @Test func `assigning registers the combination, and reports the change`() {
        let hotkeys = hotkeys()

        hotkeys.assign(Self.controlOptionP, to: .pauseOrResumeAll)

        #expect(hotkeys.combinations == [.pauseOrResumeAll: Self.controlOptionP])
        #expect(registrar.heldCombinations == [Self.controlOptionP])
        #expect(changes.values == [[.pauseOrResumeAll: Self.controlOptionP]])
    }

    @Test func `assigning another combination releases the one before`() {
        let hotkeys = hotkeys([.mute: Self.controlOptionM])

        withExtendedLifetime(hotkeys) {
            hotkeys.assign(Self.controlOptionP, to: .mute)
            registrar.press(Self.controlOptionM)
            registrar.press(Self.controlOptionP)
        }

        #expect(registrar.heldCombinations == [Self.controlOptionP])
        #expect(presses.values == [.mute])
    }

    @Test func `clearing an assignment unregisters it`() {
        let hotkeys = hotkeys([.mute: Self.controlOptionM, .nextWallpaper: Self.controlOptionN])

        hotkeys.assign(nil, to: .mute)
        registrar.press(Self.controlOptionM)

        #expect(hotkeys.combinations == [.nextWallpaper: Self.controlOptionN])
        #expect(registrar.heldCombinations == [Self.controlOptionN])
        #expect(changes.values == [[.nextWallpaper: Self.controlOptionN]])
        #expect(presses.values.isEmpty)
    }

    @Test func `assigning what an action already has changes nothing`() {
        let hotkeys = hotkeys([.mute: Self.controlOptionM])

        hotkeys.assign(Self.controlOptionM, to: .mute)
        hotkeys.assign(nil, to: .openLibrary)

        #expect(changes.values.isEmpty)
        #expect(registrar.requests == [Self.controlOptionM])
    }

    @Test func `assigning again a combination macOS refused asks for it again`() {
        registrar.heldElsewhere = [Self.controlOptionN]
        let hotkeys = hotkeys([.nextWallpaper: Self.controlOptionN])
        registrar.heldElsewhere = []

        let availability = hotkeys.availability(of: Self.controlOptionN, for: .nextWallpaper)
        hotkeys.assign(Self.controlOptionN, to: .nextWallpaper)

        #expect(availability == .free)
        #expect(registrar.heldCombinations == [Self.controlOptionN])
        #expect(changes.values.isEmpty)
    }

    @Test func `an assignment round-trips through its app state 1.1 form`() throws {
        let hotkeys = hotkeys()
        hotkeys.assign(Self.controlOptionP, to: .pauseOrResumeAll)
        hotkeys.assign(Self.controlOptionN, to: .nextWallpaper)
        var state = AppState()
        state.hotkeys = try #require(changes.values.last)

        let relaunched = FakeHotkeyRegistrar()
        let loaded = try AppState.decode(state.encode())
        let again = Hotkeys(combinations: loaded.hotkeys, registrar: relaunched, onChange: { _ in }, onPress: presses.append)
        relaunched.press(Self.controlOptionN)

        #expect(again.combinations == hotkeys.combinations)
        #expect(relaunched.held == registrar.held)
        #expect(presses.values == [.nextWallpaper])
    }

    // MARK: Carbon

    nonisolated static let modifiers: [Row<KeyCombination.Modifiers, Int>] = [
        Row("none", [], 0),
        Row("control", .control, controlKey),
        Row("option", .option, optionKey),
        Row("shift", .shift, shiftKey),
        Row("command", .command, cmdKey),
        Row("all four", [.control, .option, .shift, .command], controlKey | optionKey | shiftKey | cmdKey),
    ]

    @Test(arguments: modifiers)
    func `modifiers map to Carbon's`(row: Row<KeyCombination.Modifiers, Int>) {
        #expect(CarbonHotkeyRegistrar.carbonModifiers(row.input) == UInt32(row.expected))
    }

    /// Only with a window server to register with: a logged-in session, as on this Mac and CI's.
    nonisolated static let hasWindowServer = CGSessionCopyCurrentDictionary() != nil

    @Test(.enabled(if: hasWindowServer))
    func `registers and releases a real hotkey with Carbon`() {
        let registrar = CarbonHotkeyRegistrar()
        // ⌃⌥⇧⌘F19: a key few keyboards have, under every modifier, held for a moment.
        let obscure = KeyCombination(keyCode: UInt16(kVK_F19), modifiers: [.control, .option, .shift, .command], keyLabel: "F19")

        let first = registrar.register(obscure, id: 7)
        let again = registrar.register(obscure, id: 8)
        registrar.unregister(id: 7)
        let afterRelease = registrar.register(obscure, id: 8)
        registrar.unregister(id: 8)

        #expect(first == .registered)
        #expect(again == .taken)
        #expect(afterRelease == .registered)
    }
}

/// Collects what a closure is called with.
@MainActor
final class Recorded<Value> {
    private(set) var values: [Value] = []

    func append(_ value: Value) {
        values.append(value)
    }
}
