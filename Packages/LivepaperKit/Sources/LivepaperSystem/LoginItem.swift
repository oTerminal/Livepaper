import Foundation
import LivepaperCore
import Observation
import os
import Security
import ServiceManagement

/// What the login item asks of macOS: `SMAppService.mainApp`'s calls, all of
/// them synchronous. Injected, so that tests register nothing.
public protocol LoginItemService: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    func openSystemSettingsLoginItems()
}

extension SMAppService: LoginItemService {
    /// Opens System Settings at Login Items. Nothing drives it, so no permission is asked.
    public func openSystemSettingsLoginItems() {
        Self.openSystemSettingsLoginItems()
    }
}

/// Open at Login: the app itself as its login item, `SMAppService.mainApp`,
/// with no helper and no LaunchAgent.
///
/// `status` is macOS's, read when the item is made, after each change, and on
/// `refresh`; the row shows it and never the intent. Registering and
/// unregistering are synchronous, so the switch gets its answer in the same
/// turn. Nothing registers while translocated.
@Observable
public final class LoginItem {
    public static let logCategory = "login"

    public private(set) var status: LoginItemStatus
    /// This copy of Livepaper, kept with the intent.
    public let bundle: BundleIdentity

    @ObservationIgnored private let service: any LoginItemService
    @ObservationIgnored private let logger: Logger
    /// Whether this run's last registration left macOS unable to find the app.
    @ObservationIgnored private var registrationNotFound = false

    public init(
        service: any LoginItemService = SMAppService.mainApp,
        bundle: BundleIdentity = .current(),
        logger: Logger = Logger(subsystem: LivepaperSystem.logSubsystem, category: LoginItem.logCategory)
    ) {
        self.service = service
        self.bundle = bundle
        self.logger = logger
        status = Self.status(service.status, translocated: bundle.isTranslocated, registrationNotFound: false)
    }

    /// Reads the status again: the user can change it in System Settings at any time.
    public func refresh() {
        let now = Self.status(service.status, translocated: bundle.isTranslocated, registrationNotFound: registrationNotFound)
        if now != status { status = now }
    }

    /// Registers or unregisters, unless macOS already has what is asked, and
    /// answers the status that follows. A failure is logged, and the answer is
    /// still the real status, never what was asked.
    public func setOpenAtLogin(_ on: Bool) -> LoginItemStatus {
        let before = service.status
        let registered = before == .enabled || before == .requiresApproval
        if on, !registered {
            register()
        } else if !on, registered {
            do {
                try service.unregister()
            } catch {
                logger.error("login: unregister failed: \(LogWords.kind(of: error), privacy: .public)")
            }
        }
        refresh()
        logger.notice("login: asked \(on ? "on" : "off", privacy: .public), status \(String(describing: self.status), privacy: .public)")
        return status
    }

    public func openSystemSettingsLoginItems() {
        service.openSystemSettingsLoginItems()
    }

    /// The launch's part: `reconcileLoginItem` against the status now, carried
    /// out. Answers the intent to keep, which is `intent` itself when nothing changed.
    public func reconciling(_ intent: LoginItemIntent?) -> LoginItemIntent? {
        refresh()
        let reconciliation = reconcileLoginItem(intent: intent, status: status, bundle: bundle)
        let found = String(describing: status)
        logger.notice("login: at launch \(found, privacy: .public), \(Self.describe(reconciliation), privacy: .public)")
        switch reconciliation {
        case .nothing:
            return intent
        case .record(let kept):
            return kept
        case .register(let kept):
            return setOpenAtLogin(true).isRegistered ? kept : intent
        }
    }

    private func register() {
        guard !bundle.isTranslocated else {
            logger.notice("login: not registering while translocated")
            return
        }
        do {
            try service.register()
        } catch {
            logger.error("login: register failed: \(LogWords.kind(of: error), privacy: .public)")
        }
        registrationNotFound = service.status == .notFound
    }

    /// macOS's status as the row shows it.
    ///
    /// macOS says "not found" of an app it has never registered, as well as of
    /// one it cannot find (a bundle here that was never registered read it, as
    /// Wallper did before registering), so it is off
    /// until a registration is answered with it. A translocated copy that is not
    /// registered is not found: the row asks for a move to Applications.
    nonisolated static func status(_ status: SMAppService.Status, translocated: Bool, registrationNotFound: Bool) -> LoginItemStatus {
        switch status {
        case .enabled:
            return .on
        case .requiresApproval:
            return .needsApproval
        case .notFound where registrationNotFound:
            return .notFound
        case .notRegistered, .notFound:
            break
        @unknown default:
            break
        }
        return translocated ? .notFound : .off
    }

    private static func describe(_ reconciliation: LoginItemReconciliation) -> String {
        switch reconciliation {
        case .nothing: "nothing to do"
        case .record(let intent): "keeping the intent \(intent.openAtLogin ? "on" : "off")"
        case .register: "registering again for a copy that moved"
        }
    }
}

extension BundleIdentity {
    /// This copy of Livepaper: `Bundle.main`'s path and the designated
    /// requirement of the code running, nil when it is not signed.
    public static func current() -> BundleIdentity {
        BundleIdentity(path: Bundle.main.bundlePath, designatedRequirement: runningRequirement())
    }

    private static func runningRequirement() -> String? {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        var text: CFString?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement,
              SecRequirementCopyString(requirement, [], &text) == errSecSuccess else { return nil }
        return text as String?
    }
}
