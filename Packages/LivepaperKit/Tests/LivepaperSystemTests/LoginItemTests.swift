import Foundation
import LivepaperCore
import LivepaperSystem
import os
import ServiceManagement
import Testing

/// `SMAppService.mainApp` without macOS: a registration turns it on, or leaves
/// whatever `afterRegister` says, and then throws `registerError` if there is one.
@MainActor
final class FakeLoginItemService: LoginItemService {
    struct Refusal: Error {}

    var status: SMAppService.Status
    var afterRegister: SMAppService.Status = .enabled
    var registerError: (any Error)?
    var unregisterError: (any Error)?
    private(set) var registrations = 0
    private(set) var unregistrations = 0
    private(set) var settingsOpened = 0

    init(_ status: SMAppService.Status) {
        self.status = status
    }

    func register() throws {
        registrations += 1
        status = afterRegister
        if let registerError { throw registerError }
    }

    func unregister() throws {
        unregistrations += 1
        if let unregisterError { throw unregisterError }
        status = .notRegistered
    }

    func openSystemSettingsLoginItems() {
        settingsOpened += 1
    }
}

@MainActor
struct LoginItemTests {
    nonisolated static let applications = BundleIdentity(
        path: "/Applications/Livepaper.app", designatedRequirement: #"identifier "app.livepaper.Livepaper" and certificate leaf = H"6741""#
    )
    nonisolated static let moved = BundleIdentity(
        path: "/Users/someone/Desktop/Livepaper.app", designatedRequirement: applications.designatedRequirement
    )
    nonisolated static let translocated = BundleIdentity(
        path: "/private/var/folders/xy/abc123/T/AppTranslocation/0F1E2D3C-4B5A-6978-8796-A5B4C3D2E1F0/d/Livepaper.app",
        designatedRequirement: applications.designatedRequirement
    )

    func loginItem(_ service: FakeLoginItemService, bundle: BundleIdentity = applications) -> LoginItem {
        LoginItem(service: service, bundle: bundle, logger: Logger(subsystem: "app.livepaper.tests", category: LoginItem.logCategory))
    }

    // MARK: Status

    nonisolated static let statuses: [Row<SMAppService.Status, LoginItemStatus>] = [
        Row("not registered is off", .notRegistered, .off),
        Row("enabled is on", .enabled, .on),
        Row("requires approval is waiting for approval", .requiresApproval, .needsApproval),
        // What macOS says of an app it has never registered, seen here and by Wallper.
        Row("not found, with no registration tried, is off", .notFound, .off),
    ]

    @Test(arguments: statuses)
    func `shows macOS's status`(row: Row<SMAppService.Status, LoginItemStatus>) {
        #expect(loginItem(FakeLoginItemService(row.input)).status == row.expected)
    }

    @Test func `not found once a registration is answered with it`() {
        let service = FakeLoginItemService(.notFound)
        service.afterRegister = .notFound
        service.registerError = FakeLoginItemService.Refusal()
        let item = loginItem(service)

        #expect(item.setOpenAtLogin(true) == .notFound)
        #expect(item.status == .notFound)
    }

    @Test func `reads the status again when asked, as the user can change it in System Settings`() {
        let service = FakeLoginItemService(.enabled)
        let item = loginItem(service)

        service.status = .notRegistered
        item.refresh()

        #expect(item.status == .off)
    }

    // MARK: The switch

    @Test func `turning it on registers, and answers the status that follows in the same turn`() {
        let service = FakeLoginItemService(.notFound)
        let item = loginItem(service)

        #expect(item.setOpenAtLogin(true) == .on)
        #expect(item.status == .on)
        #expect(service.registrations == 1)
    }

    @Test func `a registration waiting for approval is answered as it is`() {
        let service = FakeLoginItemService(.notRegistered)
        service.afterRegister = .requiresApproval

        #expect(loginItem(service).setOpenAtLogin(true) == .needsApproval)
    }

    @Test func `turning it off unregisters`() {
        let service = FakeLoginItemService(.enabled)
        let item = loginItem(service)

        #expect(item.setOpenAtLogin(false) == .off)
        #expect(service.unregistrations == 1)
    }

    @Test func `asking for what macOS already has asks nothing of it`() {
        let on = FakeLoginItemService(.enabled)
        let waiting = FakeLoginItemService(.requiresApproval)
        let off = FakeLoginItemService(.notRegistered)

        #expect(loginItem(on).setOpenAtLogin(true) == .on)
        #expect(loginItem(waiting).setOpenAtLogin(true) == .needsApproval)
        #expect(loginItem(off).setOpenAtLogin(false) == .off)
        #expect([on, waiting, off].map { $0.registrations + $0.unregistrations } == [0, 0, 0])
    }

    @Test func `a failure answers the real status, never what was asked`() {
        let refusesOn = FakeLoginItemService(.notRegistered)
        refusesOn.afterRegister = .notRegistered
        refusesOn.registerError = FakeLoginItemService.Refusal()
        let refusesOff = FakeLoginItemService(.enabled)
        refusesOff.unregisterError = FakeLoginItemService.Refusal()

        #expect(loginItem(refusesOn).setOpenAtLogin(true) == .off)
        #expect(loginItem(refusesOff).setOpenAtLogin(false) == .on)
    }

    @Test func `nothing registers while translocated, and the row asks for a move to Applications`() {
        let service = FakeLoginItemService(.notFound)
        let item = loginItem(service, bundle: Self.translocated)

        #expect(item.status == .notFound)
        #expect(item.setOpenAtLogin(true) == .notFound)
        #expect(service.registrations == 0)
    }

    @Test func `opens the Login Items settings`() {
        let service = FakeLoginItemService(.requiresApproval)

        loginItem(service).openSystemSettingsLoginItems()

        #expect(service.settingsOpened == 1)
    }

    // MARK: Launch

    @Test func `a launch of another copy registers it, and keeps the intent with it`() {
        let service = FakeLoginItemService(.notFound)
        let intent = LoginItemIntent(openAtLogin: true, bundle: Self.moved)

        let kept = loginItem(service).reconciling(intent)

        #expect(kept == LoginItemIntent(openAtLogin: true, bundle: Self.applications))
        #expect(service.registrations == 1)
    }

    @Test func `a copy that could not register keeps the intent it had, to try again`() {
        let service = FakeLoginItemService(.notFound)
        service.afterRegister = .notFound
        service.registerError = FakeLoginItemService.Refusal()
        let intent = LoginItemIntent(openAtLogin: true, bundle: Self.moved)

        #expect(loginItem(service).reconciling(intent) == intent)
    }

    @Test func `the user turning it off in System Settings is kept, and nothing registers`() {
        let service = FakeLoginItemService(.notRegistered)

        let kept = loginItem(service).reconciling(LoginItemIntent(openAtLogin: true, bundle: Self.applications))

        #expect(kept == LoginItemIntent(openAtLogin: false, bundle: Self.applications))
        #expect(service.registrations == 0)
    }

    @Test func `a launch reads the status first`() {
        let service = FakeLoginItemService(.enabled)
        let item = loginItem(service)
        service.status = .notRegistered

        let kept = item.reconciling(LoginItemIntent(openAtLogin: true, bundle: Self.applications))

        #expect(kept?.openAtLogin == false)
        #expect(item.status == .off)
    }

    @Test func `nothing asked, or a translocated copy, changes nothing`() {
        let service = FakeLoginItemService(.notFound)
        let intent = LoginItemIntent(openAtLogin: true, bundle: Self.moved)

        #expect(loginItem(service).reconciling(nil) == nil)
        #expect(loginItem(service, bundle: Self.translocated).reconciling(intent) == intent)
        #expect(service.registrations == 0)
    }

    // MARK: This Mac

    @Test func `reading macOS's own status registers nothing`() {
        let before = SMAppService.mainApp.status

        let item = LoginItem()
        item.refresh()

        #expect(SMAppService.mainApp.status == before)
        #expect(!item.bundle.isTranslocated)
        #expect(item.status == loginItem(FakeLoginItemService(before)).status)
    }

    @Test func `this copy is known by its bundle's path and its designated requirement`() {
        let bundle = BundleIdentity.current()

        #expect(bundle.path == Bundle.main.bundlePath)
        #expect(bundle.designatedRequirement?.isEmpty == false)
    }
}
