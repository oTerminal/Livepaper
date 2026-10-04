import LivepaperCore
import LivepaperTestSupport
import Testing

@MainActor
struct FakeSystemServicesTests {
    nonisolated static let commandQ = KeyCombination(keyCode: 12, modifiers: .command, keyLabel: "Q")
    nonisolated static let controlOptionN = KeyCombination(keyCode: 45, modifiers: [.control, .option], keyLabel: "N")

    // MARK: Login item

    @Test func `the login item flips at once, and says so in the same turn`() {
        let services = FakeSystemServices()

        let on = services.setOpenAtLogin(true)
        let stillOn = services.loginItem
        let off = services.setOpenAtLogin(false)

        #expect([on, stillOn, off, services.loginItem] == [.on, .on, .off, .off])
    }

    @Test(arguments: [LoginItemStatus.needsApproval, .notFound])
    func `turning the login item on can answer as macOS can, for onboarding's login card`(answer: LoginItemStatus) {
        let services = FakeSystemServices()
        services.answerToTurningOn = answer

        #expect(services.setOpenAtLogin(true) == answer)
        #expect(services.loginItem == answer)
        #expect(services.setOpenAtLogin(false) == .off)
    }

    @Test(arguments: LoginItemStatus.allCases)
    func `the login item can start in any state, for the screenshots`(status: LoginItemStatus) {
        #expect(FakeSystemServices(loginItem: status).loginItem == status)
    }

    @Test func `opening the Login Items settings is remembered`() {
        let services = FakeSystemServices()

        services.openLoginItemsSettings()

        #expect(services.loginItemsSettingsOpened == 1)
    }

    // MARK: Hotkeys

    nonisolated static let takenElsewhere: [Row<KeyCombination, Void>] = [
        Row("⌘Q", commandQ, ()),
        Row("⌘W", KeyCombination(keyCode: 13, modifiers: .command, keyLabel: "W"), ()),
        Row("⌘Tab", KeyCombination(keyCode: 48, modifiers: .command, keyLabel: "Tab"), ()),
        Row("⌘Space", KeyCombination(keyCode: 49, modifiers: .command, keyLabel: "Space"), ()),
        Row("⌃Space", KeyCombination(keyCode: 49, modifiers: .control, keyLabel: "Space"), ()),
        Row("⌘H", KeyCombination(keyCode: 4, modifiers: .command, keyLabel: "H"), ()),
        Row("⌘M", KeyCombination(keyCode: 46, modifiers: .command, keyLabel: "M"), ()),
        Row("⌘,", KeyCombination(keyCode: 43, modifiers: .command, keyLabel: ","), ()),
    ]

    @Test(arguments: takenElsewhere)
    func `a combination macOS keeps is taken elsewhere`(row: Row<KeyCombination, Void>) {
        #expect(FakeSystemServices().availability(of: row.input, for: .mute) == .takenElsewhere)
    }

    @Test func `another action's combination is used by it, and an action's own is free`() {
        let services = FakeSystemServices()
        services.assign(Self.controlOptionN, to: .nextWallpaper)
        // The layout can print the key differently; the key and its modifiers are what count.
        let sameKeys = KeyCombination(keyCode: 45, modifiers: [.option, .control], keyLabel: "n")

        #expect(services.availability(of: sameKeys, for: .mute) == .usedBy(.nextWallpaper))
        #expect(services.availability(of: sameKeys, for: .nextWallpaper) == .free)
    }

    @Test func `a combination nothing has is free`() {
        let services = FakeSystemServices()
        let commandShiftQ = KeyCombination(keyCode: 12, modifiers: [.command, .shift], keyLabel: "Q")

        #expect(services.availability(of: commandShiftQ, for: .openLibrary) == .free)
        #expect(services.availability(of: Self.controlOptionN, for: .openLibrary) == .free)
    }

    @Test func `assigns and clears an action's combination`() {
        let services = FakeSystemServices()

        services.assign(Self.controlOptionN, to: .pauseOrResumeAll)
        let assigned = services.hotkeys
        services.assign(nil, to: .pauseOrResumeAll)

        #expect(assigned == [.pauseOrResumeAll: Self.controlOptionN])
        #expect(services.hotkeys.isEmpty)
    }

    @Test func `the actions' names`() {
        #expect(HotkeyAction.allCases.map(\.title) == ["Pause or Resume All", "Next Wallpaper", "Mute", "Open Library"])
    }

    @Test func `modifiers have the design system's bits`() {
        let modifiers: [KeyCombination.Modifiers] = [.control, .option, .shift, .command]

        #expect(modifiers.map(\.rawValue) == [1, 2, 4, 8])
    }

    // MARK: Leaving

    @Test func `leaving Livepaper is remembered`() async {
        let services = FakeSystemServices()

        await services.leaveLivepaper()

        #expect(services.leaveCount == 1)
    }
}
