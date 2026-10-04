/// One regular file inside the app, by its path relative to the app's folder.
public struct BundleFile: Hashable, Sendable {
    public var path: String
    /// Whether the file starts with a Mach-O or universal-binary magic number.
    public var isMachO: Bool

    public init(path: String, isMachO: Bool) {
        self.path = path
        self.isMachO = isMachO
    }

    public static func machO(_ path: String) -> BundleFile { BundleFile(path: path, isMachO: true) }
    public static func resource(_ path: String) -> BundleFile { BundleFile(path: path, isMachO: false) }
}

/// One `codesign` call: a bundle or a loose executable, relative to the app's folder,
/// the app itself being the empty path.
public struct SigningStep: Hashable, Sendable {
    public var path: String
    /// Given to `--identifier` for a loose executable; nil for a bundle, which
    /// `codesign` names from its Info.plist.
    public var identifier: String?
    /// The entitlements file, relative to the repository, given to `--entitlements`;
    /// nil signs with none.
    public var entitlements: String?

    public init(path: String, identifier: String?, entitlements: String?) {
        self.path = path
        self.identifier = identifier
        self.entitlements = entitlements
    }

    /// What `release-kit signing-order` prints for `sign.sh`: the path (`.` for the
    /// app), the identifier and the entitlements file, tab-separated, `-` for none.
    public var line: String {
        [path.isEmpty ? "." : path, identifier ?? "-", entitlements ?? "-"].joined(separator: "\t")
    }
}

/// What a bundle holds besides bundles: the loose executables, each with the
/// identifier its signature carries, and the bundles signed with entitlements.
public struct SigningRules: Hashable, Sendable {
    public var executables: [String: String]
    public var entitlements: [String: String]

    public init(executables: [String: String], entitlements: [String: String]) {
        self.executables = executables
        self.entitlements = entitlements
    }

    /// Livepaper's: Sparkle's `Autoupdate`, the ffmpeg helper, the shader
    /// tools and the `livepaper` tool, each under the identifier
    /// the build gave it; the extension with the sandbox and the library's read-only
    /// exception. Everything else that is code is a bundle's
    /// own executable. steamcmd is never bundled.
    public static let livepaper = SigningRules(
        executables: [
            "Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate": "org.sparkle-project.Sparkle.Autoupdate",
            "Contents/MacOS/ffmpeg": "app.livepaper.Livepaper.ffmpeg",
            "Contents/MacOS/glslang": "app.livepaper.Livepaper.glslang",
            "Contents/MacOS/spirv-cross": "app.livepaper.Livepaper.spirv-cross",
            "Contents/Helpers/livepaper": "app.livepaper.cli",
        ],
        entitlements: [
            "Contents/Extensions/WallpaperExtension.appex": "WallpaperExtension/WallpaperExtension.entitlements",
        ]
    )
}

public enum SigningOrderError: Error, Hashable, CustomStringConvertible {
    /// A Mach-O that is neither a bundle's executable nor one the rules name, so
    /// nothing would sign it.
    case unplaced(String)
    /// A bundle with no executable of its own name.
    case noExecutable(String)
    /// A bundle the rules give entitlements to is not in the app.
    case missingBundle(String)

    public var description: String {
        switch self {
        case .unplaced(let path): "\(path) is a Mach-O that the signing order does not place: add it to SigningRules.livepaper"
        case .noExecutable(let path): "\(path.isEmpty ? "the app" : path) has no executable of its own name"
        case .missingBundle(let path): "\(path) is not in the app"
        }
    }
}

/// The order to sign a bundle in, inside-out: every nested bundle and
/// loose executable, deepest first, so that nothing is sealed before what it holds
/// is signed, and the app last. Never `--deep`: each piece of code is one step.
///
/// - Parameters:
///   - files: every regular file in the app, symbolic links left out.
///   - appName: the app's executable name, `Livepaper`.
public func signingOrder(of files: [BundleFile], appName: String, rules: SigningRules) throws(SigningOrderError) -> [SigningStep] {
    let bundles = nestedBundles(in: files.map(\.path))
    var executablesFound = Set<String>()
    var steps: [SigningStep] = []

    for file in files where file.isMachO {
        if let identifier = rules.executables[file.path] {
            steps.append(SigningStep(path: file.path, identifier: identifier, entitlements: nil))
            continue
        }
        let owner = innermostBundle(holding: file.path, among: bundles)
        guard isExecutable(file.path, of: owner, appName: appName) else { throw .unplaced(file.path) }
        executablesFound.insert(owner)
    }
    for bundle in bundles.sorted() + [""] where !executablesFound.contains(bundle) {
        throw .noExecutable(bundle)
    }
    for bundle in rules.entitlements.keys.sorted() where !bundles.contains(bundle) {
        throw .missingBundle(bundle)
    }
    steps += bundles.map { SigningStep(path: $0, identifier: nil, entitlements: rules.entitlements[$0]) }

    // Deeper first; at one depth, by path, so a listing in any order signs alike.
    steps.sort { lhs, rhs in
        let (left, right) = (depth(lhs.path), depth(rhs.path))
        return left != right ? left > right : lhs.path < rhs.path
    }
    return steps + [SigningStep(path: "", identifier: nil, entitlements: nil)]
}

private let bundleExtensions = [".app", ".appex", ".xpc", ".framework"]

/// Every folder inside the app that is a bundle, by its extension.
private func nestedBundles(in paths: [String]) -> Set<String> {
    var bundles = Set<String>()
    for path in paths {
        let parts = path.split(separator: "/").dropLast()
        for end in parts.indices where bundleExtensions.contains(where: parts[end].hasSuffix) {
            bundles.insert(parts[...end].joined(separator: "/"))
        }
    }
    return bundles
}

private func innermostBundle(holding path: String, among bundles: Set<String>) -> String {
    bundles.filter { path.hasPrefix($0 + "/") }.max { depth($0) < depth($1) } ?? ""
}

/// Whether a file is a bundle's own executable: `Contents/MacOS/<name>` in an app,
/// extension or XPC service, `Versions/<version>/<name>` in a framework, whose other
/// copies are symbolic links and not listed.
private func isExecutable(_ path: String, of bundle: String, appName: String) -> Bool {
    guard !bundle.isEmpty else { return path == "Contents/MacOS/\(appName)" }
    let last = bundle.split(separator: "/").last.map(String.init) ?? bundle
    let name = String(last[..<(last.lastIndex(of: ".") ?? last.endIndex)])
    guard bundle.hasSuffix(".framework") else { return path == "\(bundle)/Contents/MacOS/\(name)" }
    let inside = path.dropFirst(bundle.count + 1).split(separator: "/")
    return inside.count == 3 && inside[0] == "Versions" && inside[2] == name
}

private func depth(_ path: String) -> Int {
    path.isEmpty ? 0 : path.split(separator: "/").count
}
