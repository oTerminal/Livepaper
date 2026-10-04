import Foundation
import Testing
import LivepaperWorkshop

/// Setting steamcmd up: the architectures it has code for, Rosetta, its
/// signature, and putting it in place. Valve's own archive is never fetched
/// here: an archive is made for each test, holding a copy of `/bin/ls` (signed
/// by Apple) or a script (signed by nobody) as its `steamcmd`.
struct SteamCmdToolTests {
    // MARK: Architectures and Rosetta

    static func thin(_ type: UInt32) -> Data {
        var bytes: [UInt8] = [0xCF, 0xFA, 0xED, 0xFE]
        withUnsafeBytes(of: type.littleEndian) { bytes += $0 }
        return Data(bytes + [UInt8](repeating: 0, count: 24))
    }

    static func universal(_ types: [UInt32], wide: Bool = false) -> Data {
        var bytes: [UInt8] = wide ? [0xCA, 0xFE, 0xBA, 0xBF] : [0xCA, 0xFE, 0xBA, 0xBE]
        withUnsafeBytes(of: UInt32(types.count).bigEndian) { bytes += $0 }
        for type in types {
            withUnsafeBytes(of: type.bigEndian) { bytes += $0 }
            bytes += [UInt8](repeating: 0, count: wide ? 28 : 16)
        }
        return Data(bytes)
    }

    static let arm64: UInt32 = 0x0100_000C
    static let intel: UInt32 = 0x0100_0007

    static let headers: [Row<Data, Set<MachOArchitecture>?>] = [
        Row("Valve's archive: Intel only", thin(intel), [.intel]),
        Row("Apple silicon only", thin(arm64), [.appleSilicon]),
        Row("what steamcmd updates itself to: universal", universal([intel, arm64]), [.intel, .appleSilicon]),
        Row("universal, 64-bit records", universal([intel, arm64], wide: true), [.intel, .appleSilicon]),
        Row("another processor", thin(0x0000_0012), [.other(0x12)]),
        Row("a script", Data("#!/bin/bash\n".utf8), nil),
        Row("nothing", Data(), nil),
        Row("a header cut short", Data([0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 2, 1, 0]), nil),
        Row("a universal header that claims too many slices", universal(Array(repeating: intel, count: 40)), nil),
    ]

    @Test(arguments: headers)
    func `reads which processors an executable has code for`(row: Row<Data, Set<MachOArchitecture>?>) {
        #expect(machOArchitectures(of: row.input) == row.expected)
    }

    static let rosetta: [Row<(architectures: Set<MachOArchitecture>, installed: Bool), WorkshopError?>] = [
        Row("Intel code with Rosetta", ([.intel], true), nil),
        Row("Intel code without Rosetta", ([.intel], false), .rosettaMissing),
        Row("universal code runs as it is", ([.intel, .appleSilicon], false), nil),
        Row("Apple silicon code runs as it is", ([.appleSilicon], false), nil),
        Row("code for neither", ([.other(0x12)], true), .rosettaMissing),
    ]

    @Test(arguments: rosetta)
    func `needs Rosetta only for Intel code on Apple silicon`(
        row: Row<(architectures: Set<MachOArchitecture>, installed: Bool), WorkshopError?>
    ) {
        let problem = rosettaProblem(architectures: row.input.architectures, onAppleSilicon: true, rosettaInstalled: row.input.installed)
        #expect(problem == row.expected)
    }

    // MARK: The signature

    @Test func `a program signed by the signer asked for passes, and by anyone else does not`() throws {
        let folder = try TemporaryFolder()
        let copy = folder.file("ls")
        try FileManager.default.copyItem(at: URL(filePath: "/bin/ls"), to: copy)
        #expect(CodeSignature.satisfies(copy, requirement: "anchor apple"))
        #expect(!CodeSignature.satisfies(copy, requirement: CodeSignature.valve))
    }

    @Test func `a program signed by nobody, or altered, or missing, does not pass`() throws {
        let folder = try TemporaryFolder()
        let script = folder.file("script")
        FileManager.default.createFile(atPath: script.path, contents: Data("#!/bin/sh\nexit 0\n".utf8))
        #expect(!CodeSignature.satisfies(script, requirement: "anchor apple"))

        let altered = folder.file("ls")
        var bytes = try Data(contentsOf: URL(filePath: "/bin/ls"))
        bytes[bytes.count / 2] ^= 0xFF
        try bytes.write(to: altered)
        #expect(!CodeSignature.satisfies(altered, requirement: "anchor apple"))

        #expect(!CodeSignature.satisfies(folder.file("missing"), requirement: "anchor apple"))
    }

    // MARK: Putting it in place

    /// A `.tar.gz` holding `steamcmd`, a copy of `executable`, and a file beside it.
    static func archive(of executable: URL, in folder: TemporaryFolder) throws -> URL {
        let contents = folder.folder("archive-contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: executable, to: contents.appending(path: "steamcmd"))
        FileManager.default.createFile(atPath: contents.appending(path: "steamcmd.sh").path, contents: Data("#!/bin/bash\n".utf8))
        let archive = folder.file("steamcmd_osx.tar.gz")
        let tar = Process()
        tar.executableURL = URL(filePath: "/usr/bin/tar")
        tar.arguments = ["-czf", archive.path, "-C", contents.path, "steamcmd", "steamcmd.sh"]
        try tar.run()
        tar.waitUntilExit()
        return archive
    }

    /// A download that copies the archive to a file of its own, as `URLSession` would have.
    static func fetching(_ archive: URL) -> @Sendable (URL) async throws -> URL {
        { _ in
            let copy = FileManager.default.temporaryDirectory.appending(path: "fetched-\(UUID().uuidString).tar.gz")
            try FileManager.default.copyItem(at: archive, to: copy)
            return copy
        }
    }

    static func leftovers(beside tool: SteamCmdTool) -> [String] {
        let parent = tool.folder.deletingLastPathComponent()
        return ((try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []).filter { $0.hasPrefix(".steamcmd-") }
    }

    @Test func `puts a signed steamcmd in place and checks it can run`() async throws {
        let folder = try TemporaryFolder()
        let archive = try Self.archive(of: URL(filePath: "/bin/ls"), in: folder)
        let tool = SteamCmdTool(folder: folder.folder("Livepaper/steamcmd"), requirement: "anchor apple")
        try FileManager.default.createDirectory(at: tool.folder.deletingLastPathComponent(), withIntermediateDirectories: true)

        try await tool.install(fetch: Self.fetching(archive))
        #expect(tool.isInstalled)
        #expect(FileManager.default.fileExists(atPath: tool.folder.appending(path: "steamcmd.sh").path))
        #expect(Self.leftovers(beside: tool).isEmpty)
        try tool.check(rosettaInstalled: false)
    }

    @Test func `refuses a steamcmd without the signature, and keeps the one it had`() async throws {
        let folder = try TemporaryFolder()
        let script = folder.file("script")
        FileManager.default.createFile(atPath: script.path, contents: Data("#!/bin/sh\nexit 0\n".utf8))
        let archive = try Self.archive(of: script, in: folder)
        let tool = SteamCmdTool(folder: folder.folder("Livepaper/steamcmd"), requirement: "anchor apple")
        try FileManager.default.createDirectory(at: tool.folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(filePath: "/bin/ls"), to: tool.executable)

        await #expect(throws: WorkshopError.toolUntrusted) { try await tool.install(fetch: Self.fetching(archive)) }
        try tool.check(rosettaInstalled: false)
        #expect(Self.leftovers(beside: tool).isEmpty)
    }

    @Test func `an archive that will not unpack, or will not come, leaves nothing`() async throws {
        let folder = try TemporaryFolder()
        let broken = folder.file("broken.tar.gz")
        try Data("not an archive".utf8).write(to: broken)
        let tool = SteamCmdTool(folder: folder.folder("Livepaper/steamcmd"), requirement: "anchor apple")
        try FileManager.default.createDirectory(at: tool.folder.deletingLastPathComponent(), withIntermediateDirectories: true)

        await #expect(throws: WorkshopError.toolNotDownloaded) { try await tool.install(fetch: Self.fetching(broken)) }
        await #expect(throws: WorkshopError.toolNotDownloaded) {
            try await tool.install(fetch: { _ in throw URLError(.notConnectedToInternet) })
        }
        #expect(!tool.isInstalled)
        #expect(Self.leftovers(beside: tool).isEmpty)
    }

    @Test func `a steamcmd that is not Valve's is never run`() throws {
        let folder = try TemporaryFolder()
        let tool = SteamCmdTool(folder: folder.folder("steamcmd"))
        try FileManager.default.createDirectory(at: tool.folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(filePath: "/bin/ls"), to: tool.executable)
        #expect(throws: WorkshopError.toolUntrusted) { try tool.check() }
    }

    // MARK: What steamcmd loads from its folder

    /// A steamcmd folder whose `steamcmd` passes ("anchor apple": a copy of `/bin/ls`).
    static func signedTool(in folder: TemporaryFolder) throws -> SteamCmdTool {
        let tool = SteamCmdTool(folder: folder.folder("steamcmd"), requirement: "anchor apple")
        try FileManager.default.createDirectory(at: tool.folder.appending(path: "Frameworks"), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: URL(filePath: "/bin/ls"), to: tool.executable)
        FileManager.default.createFile(atPath: tool.folder.appending(path: "steamcmd.sh").path, contents: Data("#!/bin/bash\n".utf8))
        return tool
    }

    /// A copy of `/bin/ls` signed again by nobody in particular (ad hoc), as `codesign -s -` signs.
    static func adHocProgram(at url: URL) throws {
        try FileManager.default.copyItem(at: URL(filePath: "/bin/ls"), to: url)
        let codesign = Process()
        codesign.executableURL = URL(filePath: "/usr/bin/codesign")
        codesign.arguments = ["--force", "--sign", "-", url.path]
        codesign.standardError = FileHandle.nullDevice
        try codesign.run()
        codesign.waitUntilExit()
        #expect(codesign.terminationStatus == 0)
    }

    @Test func `a library beside steamcmd, which it loads from there, must carry the signature too`() throws {
        let folder = try TemporaryFolder()
        let tool = try Self.signedTool(in: folder)
        try FileManager.default.copyItem(at: URL(filePath: "/bin/ls"), to: tool.folder.appending(path: "libtier0_s.dylib"))
        try tool.check(rosettaInstalled: false)

        try Self.adHocProgram(at: tool.folder.appending(path: "Frameworks/libz.1.dylib"))
        #expect(throws: WorkshopError.toolUntrusted) { try tool.check(rosettaInstalled: false) }
    }

    @Test func `an altered library beside steamcmd is refused`() throws {
        let folder = try TemporaryFolder()
        let tool = try Self.signedTool(in: folder)
        var bytes = try Data(contentsOf: URL(filePath: "/bin/ls"))
        bytes[bytes.count / 2] ^= 0xFF
        try bytes.write(to: tool.folder.appending(path: "steamclient.dylib"))
        #expect(throws: WorkshopError.toolUntrusted) { try tool.check(rosettaInstalled: false) }
    }

    @Test func `a link out of steamcmd's folder is refused, even to a signed program`() throws {
        let folder = try TemporaryFolder()
        let tool = try Self.signedTool(in: folder)
        try FileManager.default.createSymbolicLink(at: tool.folder.appending(path: "Frameworks/Current"), withDestinationURL: tool.folder)
        try tool.check(rosettaInstalled: false)

        try FileManager.default.createSymbolicLink(
            at: tool.folder.appending(path: "libiconv.2.dylib"), withDestinationURL: URL(filePath: "/bin/ls")
        )
        #expect(throws: WorkshopError.toolUntrusted) { try tool.check(rosettaInstalled: false) }
    }

    @Test func `the ad hoc libsteaminput Valve ships is let through, and the same bytes under another name are not`() throws {
        let folder = try TemporaryFolder()
        let tool = try Self.signedTool(in: folder)
        try Self.adHocProgram(at: tool.folder.appending(path: "libsteaminput.dylib"))
        try tool.check(rosettaInstalled: false)

        try FileManager.default.copyItem(
            at: tool.folder.appending(path: "libsteaminput.dylib"), to: tool.folder.appending(path: "libsteamclient.dylib")
        )
        #expect(throws: WorkshopError.toolUntrusted) { try tool.check(rosettaInstalled: false) }
    }

    @Test func `the archive is fetched from Valve over https only`() async {
        await #expect(throws: URLError.self) { _ = try await SteamCmdTool.download(URL(string: "http://steamcdn-a.akamaihd.net/x")!) }
        #expect(SteamCmdTool.archive.scheme == "https")
    }

    @Test func `lives in a folder of its own inside Livepaper's folder in Application Support`() {
        let tool = SteamCmdTool(home: URL(filePath: "/Users/someone", directoryHint: .isDirectory))
        #expect(tool.executable.path == "/Users/someone/Library/Application Support/Livepaper/Steam/steamcmd/steamcmd")
    }
}
