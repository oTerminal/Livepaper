/// Which copy of Livepaper is running: where its bundle is, and the requirement
/// its code signature meets.
///
/// A copy moved to another folder, or built and signed anew, is another
/// identity. An update signed with the same certificate and replaced in place
/// is the same one: its path and designated requirement do not change.
public struct BundleIdentity: Hashable, Codable, Sendable {
    /// The bundle's path, as `Bundle.main` gives it.
    public var path: String
    /// The designated requirement, as text; nil when the code is not signed.
    public var designatedRequirement: String?

    public init(path: String, designatedRequirement: String?) {
        self.path = path
        self.designatedRequirement = designatedRequirement
    }

    /// Run from the random, read-only folder Gatekeeper copies a downloaded app
    /// to when it is opened where it was downloaded. Nothing is registered or
    /// written then: the next launch would be from another path.
    public var isTranslocated: Bool {
        path.contains("/AppTranslocation/")
    }
}

/// What the user last asked of Open at Login, kept with the copy of Livepaper
/// that asked, so that a launch can tell a copy that moved from the user
/// turning the item off in System Settings.
public struct LoginItemIntent: Hashable, Codable, Sendable {
    public var openAtLogin: Bool
    public var bundle: BundleIdentity

    public init(openAtLogin: Bool, bundle: BundleIdentity) {
        self.openAtLogin = openAtLogin
        self.bundle = bundle
    }
}

/// What a launch does about the login item. The caller carries it out.
public enum LoginItemReconciliation: Hashable, Sendable {
    /// macOS and the intent agree, nothing has been asked yet, or this copy is translocated.
    case nothing
    /// Keep this intent, and leave macOS as it is.
    case record(LoginItemIntent)
    /// Another copy of Livepaper was asked to open at login: register this one,
    /// and keep this intent once macOS reports it registered. A copy that could
    /// not register keeps the intent it had, so that the next launch tries again.
    case register(LoginItemIntent)
}

extension LoginItemStatus {
    /// macOS holds a registration: on, or waiting for the user to allow it.
    public var isRegistered: Bool {
        self == .on || self == .needsApproval
    }
}

/// The login item at every launch. macOS's status is what the user sees, and
/// the intent gives way to it except where a copy that moved explains it:
///
/// - Registered, on or waiting for approval: the intent is on, kept with this copy.
/// - Not registered, off or not found, and asked on: by this copy, the user
///   turned it off in System Settings, which is respected and kept as off; by
///   another copy, this one registers again.
/// - Not registered and asked off: nothing, whichever copy asked.
///
/// Nothing asked yet, or a translocated copy, changes nothing.
public func reconcileLoginItem(intent: LoginItemIntent?, status: LoginItemStatus, bundle: BundleIdentity) -> LoginItemReconciliation {
    guard let intent, !bundle.isTranslocated else { return .nothing }
    if status.isRegistered {
        let registered = LoginItemIntent(openAtLogin: true, bundle: bundle)
        return registered == intent ? .nothing : .record(registered)
    }
    guard intent.openAtLogin else { return .nothing }
    if intent.bundle == bundle {
        return .record(LoginItemIntent(openAtLogin: false, bundle: bundle))
    }
    return .register(LoginItemIntent(openAtLogin: true, bundle: bundle))
}
