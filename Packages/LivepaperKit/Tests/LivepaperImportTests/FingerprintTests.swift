import Foundation
import Testing
import LivepaperCore
import LivepaperImport

struct FingerprintTests {
    let folder: TemporaryFolder

    init() throws {
        folder = try TemporaryFolder()
    }

    @Test func `is the SHA-256 of the file's bytes`() async throws {
        // The test vector from FIPS 180-2.
        let file = try folder.write("abc", to: "abc.mp4")

        let fingerprint = try await fingerprint(of: file)

        #expect(fingerprint == Fingerprint(sha256: "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"))
    }

    @Test func `the same bytes under another name have the same fingerprint, other bytes another`() async throws {
        let source = try Fixture.url("plain-h264.mp4")
        let copy = folder.file("Holiday (copy 2).mov")
        try FileManager.default.copyItem(at: source, to: copy)

        let expected = try await fingerprint(of: source)

        #expect(try await fingerprint(of: copy) == expected)
        #expect(try await fingerprint(of: Fixture.url("long-audio.mp4")) != expected)
    }

    @Test func `a file larger than one read is hashed whole`() async throws {
        // One million times "a", another FIPS 180-2 vector, read in pieces of 64 KB.
        let file = try folder.write(String(repeating: "a", count: 1_000_000), to: "a.bin")

        let fingerprint = try await fingerprint(of: file, chunkSize: 65_536)

        #expect(fingerprint == Fingerprint(sha256: "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0"))
    }
}
