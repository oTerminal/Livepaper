/// Where this copy of Livepaper runs, as the app reads it before anything is
/// registered.
public struct InstallLocation: Hashable, Sendable {
    /// The bundle's path, as `Bundle.main` gives it.
    public var bundlePath: String
    /// `SecTranslocateIsTranslocatedURL`'s answer; nil when it could not be
    /// asked, and then `/AppTranslocation/` in the path stands in for it.
    public var isTranslocated: Bool?
    /// Whether the bundle's volume can be written: false on a mounted disk image.
    public var isVolumeWritable: Bool

    public init(bundlePath: String, isTranslocated: Bool?, isVolumeWritable: Bool) {
        self.bundlePath = bundlePath
        self.isTranslocated = isTranslocated
        self.isVolumeWritable = isVolumeWritable
    }
}

/// What a launch does about where Livepaper runs, before anything else.
public enum InstallDecision: Hashable, Sendable {
    /// Livepaper starts.
    case proceed
    /// Run from the disk image, or from where Gatekeeper copied it: nothing can
    /// be kept from here, so the user is asked to drag it to Applications, and
    /// nothing starts.
    case askForDrag
    /// Writable, but outside both Applications folders: Livepaper offers to
    /// move itself to `/Applications`, and starts if the user says Not Now.
    case offerMove
}

/// Decides what a launch does about where Livepaper runs.
///
/// - Translocated, or on a read-only volume outside the Applications folders:
///   the drag. Not Now never answered that, so it is asked whatever was declined.
/// - In `/Applications` or `~/Applications`, at any depth: carries on.
/// - Elsewhere, at a path the user answered Not Now for: carries on.
/// - Elsewhere: offers the move.
///
/// Paths are compared component by component, so `/Applications Old` and
/// `/ApplicationsX` are not Applications, a trailing or doubled slash changes
/// nothing, and `..` climbs out. The comparison ignores case, as the APFS
/// volume `/Applications` and the home folder live on does by default.
///
/// - Parameters:
///   - declinedPaths: The bundle paths the user answered Not Now for.
public func installDecision(_ location: InstallLocation, homeDirectory: String, declinedPaths: Set<String>) -> InstallDecision {
    let bundle = InstallPath(location.bundlePath)
    let isTranslocated = location.isTranslocated ?? location.bundlePath.contains("/AppTranslocation/")
    if isTranslocated { return .askForDrag }
    let applications = [InstallPath("/Applications"), InstallPath(homeDirectory).appending("Applications")]
    if applications.contains(where: { bundle.isInside($0) }) { return .proceed }
    if !location.isVolumeWritable { return .askForDrag }
    if declinedPaths.contains(where: { InstallPath($0) == bundle }) { return .proceed }
    return .offerMove
}

/// An absolute path as its components: empty and `.` components dropped, `..`
/// taking the one before it away, and each compared without case.
private struct InstallPath: Equatable {
    let components: [String]

    init(_ path: String) {
        var components: [String] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".": continue
            case "..": _ = components.popLast()
            default: components.append(component.lowercased())
            }
        }
        self.components = components
    }

    private init(components: [String]) {
        self.components = components
    }

    func appending(_ component: String) -> InstallPath {
        InstallPath(components: components + [component.lowercased()])
    }

    /// Strictly inside `folder`, at any depth.
    func isInside(_ folder: InstallPath) -> Bool {
        components.count > folder.components.count && components.starts(with: folder.components)
    }
}
