import CryptoKit
import Foundation
import ReleaseKit

// The release scripts' one way into ReleaseKit: reads files, prints what a script
// needs, and exits non-zero with the reason on a refusal. It runs no other program
// and never prints a secret.

let usage = """
    usage: release-kit <command> [options]

      version [--project project.yml] [--tag <tag>] [--appcast <file>]
          Prints "<X.Y.Z> <build>"; refuses a wrong tag, or a build not above the appcast's last.
      signing-order <app>
          Prints sign.sh's steps, innermost first: path, identifier, entitlements, tab-separated.
      machos <app>
          Prints the path of every Mach-O in the app, for checking each one's signature.
      requirement check --recorded <file> < codesign-output
          Refuses a designated requirement that designated-requirement.txt does not record.
      requirement adhoc < codesign-output
          Passes only for an ad-hoc signature (the dry run's).
      requirement certificate --recorded <file> --sha1 <hash>
          Refuses a certificate whose SHA-1 is not the recorded leaf.
      requirement record --sha1 <hash> --identifier <id>...
          Prints designated-requirement.txt for that certificate.
      changelog <X.Y.Z> [--changelog CHANGELOG.md]
          Prints the version's section: the release's notes.
      appcast empty --feed-url <url>
          Prints a feed of no releases, for the appcast branch before the first.
      appcast last [--appcast <file>]
          Prints the appcast's last build, or nothing for an empty or missing feed.
      appcast merge --generated <file> --url <zip-url> --feed-url <url> [--appcast <file>] [--changelog CHANGELOG.md]
          Prints the appcast with the release generate_appcast signed added, its notes from the changelog.
      notices --root <repo> (--write | --check | --out <dir>)
          Writes, checks, or puts in <dir> the notices: NOTICES.txt and Credits.rtf; and the README's requirement.
      throwaway-key <dir>
          Makes an EdDSA key pair for a dry run: the private key in <dir>, the public key printed.
    """

struct Refusal: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

/// The arguments after the command: `--name value` options, `--flag`s and the rest in order.
struct Arguments {
    var positional: [String] = []
    var options: [String: [String]] = [:]

    init(_ arguments: some Sequence<String>) {
        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            if argument.hasPrefix("--") {
                let name = String(argument.dropFirst(2))
                if ["write", "check"].contains(name) {
                    options[name, default: []].append("")
                } else if let value = iterator.next() {
                    options[name, default: []].append(value)
                }
            } else {
                positional.append(argument)
            }
        }
    }

    func option(_ name: String) -> String? { options[name]?.last }

    func required(_ name: String) throws -> String {
        guard let value = option(name) else { throw Refusal("--\(name) is required") }
        return value
    }

    func flag(_ name: String) -> Bool { options[name] != nil }
}

func read(_ path: String) throws -> String {
    do {
        return try String(contentsOfFile: path, encoding: .utf8)
    } catch {
        throw Refusal("cannot read \(path)")
    }
}

/// The file's text, or nil when there is no such file.
func readIfThere(_ path: String?) throws -> String? {
    guard let path, FileManager.default.fileExists(atPath: path) else { return nil }
    return try read(path)
}

func readStandardInput() -> String {
    String(bytes: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8) ?? ""
}

func write(_ text: String, to path: String) throws {
    try text.write(toFile: path, atomically: true, encoding: .utf8)
}

// MARK: Commands

func version(_ arguments: Arguments) throws {
    let version = try ReleaseVersion(projectYML: read(arguments.option("project") ?? "project.yml"))
    if let tag = arguments.option("tag") { try version.check(tag: tag) }
    if let feed = try readIfThere(arguments.option("appcast")) {
        try version.check(after: Appcast(xml: feed).lastBuild)
    }
    print("\(version.marketing) \(version.build)")
}

func signingOrder(_ arguments: Arguments) throws {
    let (appName, files) = try bundleFiles(arguments)
    for step in try ReleaseKit.signingOrder(of: files, appName: appName, rules: .livepaper) {
        print(step.line)
    }
}

func machOs(_ arguments: Arguments) throws {
    for file in try bundleFiles(arguments).files where file.isMachO {
        print(file.path)
    }
}

/// Every regular file in the app named by the first argument, symbolic links left out.
func bundleFiles(_ arguments: Arguments) throws -> (appName: String, files: [BundleFile]) {
    guard let app = arguments.positional.first else { throw Refusal("the app is required") }
    let appURL = URL(filePath: app, directoryHint: .isDirectory).standardizedFileURL
    let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
    guard let walk = FileManager.default.enumerator(at: appURL, includingPropertiesForKeys: keys) else {
        throw Refusal("cannot read \(app)")
    }
    var files: [BundleFile] = []
    for case let url as URL in walk {
        let values = try url.resourceValues(forKeys: Set(keys))
        guard values.isRegularFile == true, values.isSymbolicLink != true else { continue }
        let path = String(url.standardizedFileURL.path.dropFirst(appURL.path.count + 1))
        files.append(BundleFile(path: path, isMachO: try isMachO(url)))
    }
    return (appURL.deletingPathExtension().lastPathComponent, files.sorted { $0.path < $1.path })
}

/// Mach-O and universal-binary magic numbers, in either byte order.
func isMachO(_ url: URL) throws -> Bool {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    guard let head = try handle.read(upToCount: 4), head.count == 4 else { return false }
    let magic = head.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
    return [0xFEED_FACE, 0xFEED_FACF, 0xCEFA_EDFE, 0xCFFA_EDFE, 0xCAFE_BABE, 0xBEBA_FECA].contains(magic)
}

func requirement(_ arguments: Arguments) throws {
    switch arguments.positional.first {
    case "check":
        let recorded = try RecordedRequirements(file: read(arguments.required("recorded")))
        let actual = try DesignatedRequirement(codesignOutput: readStandardInput())
        try recorded.check(actual)
        print("designated => \(actual)")
    case "adhoc":
        do {
            _ = try DesignatedRequirement(codesignOutput: readStandardInput())
            throw Refusal("the dry run's signature is not ad-hoc")
        } catch RequirementError.adHoc {
            print("designated => cdhash (ad-hoc, the dry run's)")
        }
    case "certificate":
        let recorded = try RecordedRequirements(file: read(arguments.required("recorded")))
        try recorded.checkCertificate(sha1: arguments.required("sha1"))
        print("certificate leaf \(recorded.leaf) is the recorded one")
    case "record":
        let leaf = try arguments.required("sha1").replacingOccurrences(of: ":", with: "").lowercased()
        guard leaf.count == 40, leaf.allSatisfy(\.isHexDigit) else { throw Refusal("--sha1 is not a SHA-1") }
        let identifiers = arguments.options["identifier"] ?? []
        guard !identifiers.isEmpty else { throw Refusal("--identifier is required") }
        print("""
            # The designated requirement of every Livepaper release: the app's
            # and the extension's, under the "Livepaper Release" certificate. Written once by
            # Tools/release/make-cert.sh; a release whose signature says anything else is refused.
            """)
        for identifier in identifiers {
            print("designated => \(DesignatedRequirement(identifier: identifier, leaf: leaf))")
        }
    default:
        throw Refusal("requirement check | adhoc | certificate | record")
    }
}

func changelog(_ arguments: Arguments) throws {
    guard let version = arguments.positional.first else { throw Refusal("changelog needs the version") }
    print(try Changelog.section(for: version, in: read(arguments.option("changelog") ?? "CHANGELOG.md")))
}

func appcast(_ arguments: Arguments) throws {
    let existing = try readIfThere(arguments.option("appcast")).map(Appcast.init(xml:))
    switch arguments.positional.first {
    case "empty":
        guard let feedURL = URL(string: try arguments.required("feed-url")) else { throw Refusal("--feed-url must be a URL") }
        print(Appcast(feedURL: feedURL, entries: []).xml, terminator: "")
    case "last":
        if let last = existing?.lastBuild { print(last) }
    case "merge":
        let generated = try Appcast(xml: read(arguments.required("generated")))
        guard generated.entries.count == 1, var entry = generated.entries.first else {
            throw Refusal("generate_appcast's feed holds \(generated.entries.count) entries, not the one release")
        }
        guard let url = URL(string: try arguments.required("url")), let feedURL = URL(string: try arguments.required("feed-url")) else {
            throw Refusal("--url and --feed-url must be URLs")
        }
        let notes = try Changelog.section(for: entry.version, in: read(arguments.option("changelog") ?? "CHANGELOG.md"))
        entry.url = url
        entry.notesHTML = ReleaseNotes.html(markdown: notes)
        if entry.pubDate.isEmpty { entry.pubDate = rfc822(Date()) }
        let feed = existing ?? Appcast(feedURL: feedURL, entries: [])
        try existing.map { try ReleaseVersion(marketing: entry.version, build: entry.build).check(after: $0.lastBuild) }
        var merged = try feed.merging(entry)
        merged.feedURL = feedURL
        print(merged.xml, terminator: "")
    default:
        throw Refusal("appcast empty | last | merge")
    }
}

func rfc822(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(identifier: "UTC")
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
    return formatter.string(from: date)
}

func notices(_ arguments: Arguments) throws {
    let root = URL(filePath: try arguments.required("root"), directoryHint: .isDirectory)
    func path(_ relative: String) -> String { root.appending(path: relative).path }
    let inputs = try NoticeInputs(
        ffmpegBuildInfo: read(path("Helpers/ffmpeg/out/BUILD-INFO.txt")),
        shaderToolsBuildInfo: read(path("Helpers/shader-tools/out/BUILD-INFO.txt")),
        sparkleEnv: read(path("Tools/release/sparkle.env")),
        notice: read(path("NOTICE")),
        provenance: read(path("Resources/Samples/PROVENANCE.md")),
        release: ReleaseVersion(projectYML: read(path("project.yml")))
    )
    let text = Notices.text(inputs)
    let credits = Notices.rtf(inputs)
    // The README carries the requirement in full, once make-cert.sh has recorded it.
    let requirement = try readIfThere(path("Tools/release/designated-requirement.txt")).map {
        try RecordedRequirements(file: $0).requirements.map { "designated => \($0)" }.joined(separator: "\n") + "\n"
    } ?? "Not made yet: Tools/release/make-cert.sh records it with the certificate, before the first release.\n"
    let readme = try read(path("README.md"))
    if arguments.flag("write") {
        try write(credits, to: path("Resources/Credits.rtf"))
        let updated = try Notices.readme(readme, section: "requirement", carrying: requirement)
        try write(updated, to: path("README.md"))
        print("wrote Resources/Credits.rtf, and README.md's requirement")
    }
    if arguments.flag("check") {
        var stale: [String] = []
        if try readIfThere(path("Resources/Credits.rtf")) != credits { stale.append("Resources/Credits.rtf") }
        if try Notices.readmeText(readme, section: "requirement") + "\n" != requirement { stale.append("README.md's requirement") }
        guard stale.isEmpty else {
            throw Refusal("\(stale.joined(separator: ", ")) differ from what ships: run make notices and commit")
        }
        print("Credits.rtf carries the notices, and README.md the requirement, that ship")
    }
    if let out = arguments.option("out") {
        try write(text, to: URL(filePath: out).appending(path: "NOTICES.txt").path)
        print("wrote \(out)/NOTICES.txt")
    }
}

func throwawayKey(_ arguments: Arguments) throws {
    guard let directory = arguments.positional.first else { throw Refusal("throwaway-key needs a folder") }
    let key = Curve25519.Signing.PrivateKey()
    let file = URL(filePath: directory).appending(path: "throwaway-ed25519.txt")
    // generate_appcast's --ed-key-file reads the base64 of the 32-byte seed.
    FileManager.default.createFile(
        atPath: file.path, contents: Data(key.rawRepresentation.base64EncodedString().utf8), attributes: [.posixPermissions: 0o600]
    )
    print(key.publicKey.rawRepresentation.base64EncodedString())
}

// MARK: Main

let commandLine = CommandLine.arguments.dropFirst()
let arguments = Arguments(commandLine.dropFirst())
do {
    switch commandLine.first {
    case "version": try version(arguments)
    case "signing-order": try signingOrder(arguments)
    case "machos": try machOs(arguments)
    case "requirement": try requirement(arguments)
    case "changelog": try changelog(arguments)
    case "appcast": try appcast(arguments)
    case "notices": try notices(arguments)
    case "throwaway-key": try throwawayKey(arguments)
    default:
        print(usage)
        exit(commandLine.first == nil || commandLine.first == "help" ? 0 : 64)
    }
} catch {
    FileHandle.standardError.write(Data("release-kit: refused: \(error)\n".utf8))
    exit(1)
}
