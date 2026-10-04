import Foundation
import Security

/// A processor a Mach-O executable has code for.
public enum MachOArchitecture: Hashable, Sendable {
    case appleSilicon
    case intel
    case other(Int32)
}

/// The architectures in a Mach-O file's header, universal or thin; nil when it is not one.
public func machOArchitectures(of header: Data) -> Set<MachOArchitecture>? {
    let bytes = [UInt8](header.prefix(4_096))
    func word(_ offset: Int, bigEndian: Bool) -> UInt32? {
        guard offset + 4 <= bytes.count else { return nil }
        let value = bytes[offset..<offset + 4].reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
        return bigEndian ? value : value.byteSwapped
    }
    func architecture(_ type: UInt32) -> MachOArchitecture {
        switch type {
        case 0x0100_000C: .appleSilicon
        case 0x0100_0007: .intel
        default: .other(Int32(bitPattern: type))
        }
    }
    switch word(0, bigEndian: true) {
    case 0xCAFE_BABE, 0xCAFE_BABF:
        // Universal: a count, then one record per slice (20 bytes each, 32 for the 64-bit form).
        let stride = word(0, bigEndian: true) == 0xCAFE_BABF ? 32 : 20
        guard let count = word(4, bigEndian: true), count > 0, count < 32 else { return nil }
        var found: Set<MachOArchitecture> = []
        for slice in 0..<Int(count) {
            guard let type = word(8 + slice * stride, bigEndian: true) else { return nil }
            found.insert(architecture(type))
        }
        return found
    case 0xCFFA_EDFE, 0xCEFA_EDFE:
        // Thin, little-endian: the processor type follows the magic.
        return word(4, bigEndian: false).map { [architecture($0)] }
    default:
        return nil
    }
}

/// Whether an executable can run on this Mac: an Apple silicon Mac runs Intel
/// code only through Rosetta. Nil when it can run.
public func rosettaProblem(
    architectures: Set<MachOArchitecture>, onAppleSilicon: Bool, rosettaInstalled: Bool
) -> WorkshopError? {
    let native: MachOArchitecture = onAppleSilicon ? .appleSilicon : .intel
    if architectures.contains(native) { return nil }
    if onAppleSilicon, architectures.contains(.intel), rosettaInstalled { return nil }
    return .rosettaMissing
}

/// Whether Rosetta is installed: the runtime it puts on the system is there.
public func isRosettaInstalled() -> Bool {
    FileManager.default.fileExists(atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime")
}

/// Whether a file starts as a Mach-O file does, thin or universal, of either byte order.
func isMachO(_ header: Data) -> Bool {
    let magic = header.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) }
    return header.count >= 4 && [0xCFFA_EDFE, 0xCEFA_EDFE, 0xFEED_FACF, 0xFEED_FACE, 0xCAFE_BABE, 0xCAFE_BABF].contains(magic)
}

extension MachOArchitecture {
    /// The processor type in the header, as the Security framework takes it.
    var cpuType: Int32 {
        switch self {
        case .appleSilicon: 0x0100_000C
        case .intel: 0x0100_0007
        case .other(let type): type
        }
    }
}

/// The check a Mach-O file must pass before it is run or loaded: signed,
/// unaltered, and by the signer the requirement names.
public enum CodeSignature {
    /// Valve's Developer ID (team MXGJJ98X76), under Apple's root. Both the
    /// steamcmd in Valve's archive and the one it updates itself to carry it
    /// (checked on 2026-09-23).
    public static let valve = #"anchor apple generic and certificate leaf[subject.OU] = "MXGJJ98X76""#

    /// Every processor's code in the file is checked on its own: Valve's
    /// universal `steamclient.dylib` passes for each and fails as a whole with
    /// "an internal error" (2026-09-23). A bundle's resources are not checked,
    /// since nothing loads them as code, and Valve's Breakpad framework carries
    /// a header changed after it was signed. With no requirement, any valid
    /// signature passes, an ad hoc one included.
    public static func satisfies(_ file: URL, requirement: String?) -> Bool {
        let header = (try? FileHandle(forReadingFrom: file)).flatMap { try? $0.read(upToCount: 4_096) } ?? Data()
        guard let architectures = machOArchitectures(of: header), !architectures.isEmpty else { return false }
        var parsed: SecRequirement?
        if let requirement {
            guard SecRequirementCreateWithString(requirement as CFString, [], &parsed) == errSecSuccess, parsed != nil else { return false }
        }
        let flags = SecCSFlags(rawValue: SecCSFlags.RawValue(kSecCSStrictValidate) | SecCSFlags.RawValue(kSecCSDoNotValidateResources))
        return architectures.allSatisfy { architecture in
            var code: SecStaticCode?
            let slice = [kSecCodeAttributeArchitecture as String: NSNumber(value: architecture.cpuType)] as CFDictionary
            guard SecStaticCodeCreateWithPathAndAttributes(file as CFURL, [], slice, &code) == errSecSuccess, let code else { return false }
            return SecStaticCodeCheckValidity(code, flags, parsed) == errSecSuccess
        }
    }
}

/// Valve's steamcmd, kept in Livepaper's folder in Application Support
/// (`Steam/steamcmd/`), fetched from Valve on first use and never bundled.
///
/// What Valve's archive holds is checked before anything in it runs, and again
/// before each start of steamcmd, since it updates itself: the executable, and
/// every program and library in its folder, which it loads from there, must
/// carry Valve's signature (`CodeSignature.valve`). Valve publishes no checksum,
/// and a checksum of the archive would say nothing of the steamcmd that
/// replaces it minutes later.
public struct SteamCmdTool: Sendable {
    /// Valve's macOS steamcmd. Unchanged since 2 April 2020 (its Last-Modified on 2026-09-23).
    public static let archive = URL(string: "https://steamcdn-a.akamaihd.net/client/installer/steamcmd_osx.tar.gz")!

    /// The one library Valve's update puts in the folder signed ad hoc, not
    /// with its Developer ID (seen 2026-09-23). No Valve program names it, so
    /// nothing loads it; it has only to be unaltered, and only under this name,
    /// in the folder itself.
    public static let signedAdHocByValve: Set<String> = ["libsteaminput.dylib"]

    public let folder: URL
    /// The signature steamcmd must carry. Valve's, but for tests.
    public let requirement: String

    public init(folder: URL, requirement: String = CodeSignature.valve) {
        self.folder = folder
        self.requirement = requirement
    }

    /// In a folder of its own inside Livepaper's folder in Application Support:
    /// steamcmd puts a `Frameworks` link in the folder above its own, which
    /// would otherwise be the library's.
    public init(home: URL) {
        self.init(folder: home.appending(path: "Library/Application Support/Livepaper/Steam/steamcmd", directoryHint: .isDirectory))
    }

    public var executable: URL { folder.appending(path: "steamcmd", directoryHint: .notDirectory) }

    public var isInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: executable.path)
    }

    /// Checks steamcmd can and may run here: Valve's signature on it and on
    /// everything in its folder it could load, and Rosetta if it has only Intel code.
    public func check(rosettaInstalled: Bool = isRosettaInstalled()) throws(WorkshopError) {
        guard CodeSignature.satisfies(executable, requirement: requirement) else { throw .toolUntrusted }
        try checkFolder()
        let header = (try? FileHandle(forReadingFrom: executable)).flatMap { try? $0.read(upToCount: 4_096) } ?? Data()
        guard let architectures = machOArchitectures(of: header) else { throw .toolUntrusted }
        if let problem = rosettaProblem(architectures: architectures, onAppleSilicon: isAppleSilicon, rosettaInstalled: rosettaInstalled) {
            throw problem
        }
    }

    /// steamcmd starts with its folder as `DYLD_LIBRARY_PATH` and
    /// `DYLD_FRAMEWORK_PATH`, as `steamcmd.sh` starts it, so a library there by
    /// the name of any it loads, the system's included, would be loaded instead.
    /// Every Mach-O file anywhere in the folder must carry the signature, and a
    /// symbolic link must not lead out of it.
    private func checkFolder() throws(WorkshopError) {
        let root = folder.resolvingSymlinksInPath().standardizedFileURL.path
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let items = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys)) else { throw .toolUntrusted }
        for case let item as URL in items {
            let values = try? item.resourceValues(forKeys: keys)
            if values?.isSymbolicLink == true {
                let target = item.resolvingSymlinksInPath().standardizedFileURL.path
                guard target == root || target.hasPrefix(root + "/") else { throw .toolUntrusted }
                // What it leads to is in the folder, and is checked there.
                continue
            }
            guard values?.isRegularFile == true else { continue }
            let header = (try? FileHandle(forReadingFrom: item)).flatMap { try? $0.read(upToCount: 4) } ?? Data()
            guard isMachO(header) else { continue }
            let isValvesAdHoc = Self.signedAdHocByValve.contains(item.lastPathComponent)
                && item.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.path == root
            guard CodeSignature.satisfies(item, requirement: isValvesAdHoc ? nil : requirement) else { throw .toolUntrusted }
        }
    }

    /// Fetches Valve's archive, unpacks it beside the folder, checks the
    /// signature, then puts it in place with a rename. Nothing is left behind if
    /// any step fails, and a steamcmd already there is replaced only by one that
    /// passed. `fetch` downloads the archive to a file of its own.
    public func install(
        from archive: URL = SteamCmdTool.archive,
        fetch: @Sendable (URL) async throws -> URL = SteamCmdTool.download
    ) async throws(WorkshopError) {
        let files = FileManager.default
        let parent = folder.deletingLastPathComponent()
        let staging = parent.appending(path: ".steamcmd-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? files.removeItem(at: staging) }

        let downloaded: URL
        do {
            downloaded = try await fetch(archive)
        } catch {
            throw .toolNotDownloaded
        }
        defer { try? files.removeItem(at: downloaded) }

        do {
            try files.createDirectory(at: staging, withIntermediateDirectories: true)
            try await unpack(downloaded, into: staging)
        } catch {
            throw .toolNotDownloaded
        }
        let unpacked = SteamCmdTool(folder: staging, requirement: requirement)
        guard CodeSignature.satisfies(unpacked.executable, requirement: requirement) else { throw .toolUntrusted }

        do {
            if files.fileExists(atPath: folder.path) { try files.removeItem(at: folder) }
            try files.moveItem(at: staging, to: folder)
        } catch {
            throw .toolNotDownloaded
        }
    }

    /// Downloads to a file of its own, over https only.
    public static func download(_ url: URL) async throws -> URL {
        guard url.scheme == "https" else { throw URLError(.unsupportedURL) }
        let (file, response) = try await URLSession.shared.download(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            try? FileManager.default.removeItem(at: file)
            throw URLError(.badServerResponse)
        }
        return file
    }

    /// `tar` with a fixed argument list: the archive, and the folder it may write into.
    private func unpack(_ archive: URL, into folder: URL) async throws {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/tar")
        process.arguments = ["-xzf", archive.path, "-C", folder.path]
        process.environment = [:]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            process.terminationHandler = { process in
                if process.terminationReason == .exit, process.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: CocoaError(.fileReadCorruptFile))
                }
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: error)
            }
        }
    }

    private var isAppleSilicon: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }
}
