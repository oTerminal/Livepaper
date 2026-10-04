import Foundation
import Testing
@testable import LivepaperCore

struct DisplayIdentityTests {
    @Test func `survives a JSON round trip`() throws {
        let identity = DisplayIdentity(uuid: UUID())

        let data = try JSONEncoder().encode(identity)
        let decoded = try JSONDecoder().decode(DisplayIdentity.self, from: data)

        #expect(decoded == identity)
    }

    @Test func `can key a dictionary of assignments`() throws {
        let uuid = try #require(UUID(uuidString: "37D8832A-2D66-02CA-B9F7-8F30A301B230"))
        let assignments = [DisplayIdentity(uuid: uuid): "ocean"]

        #expect(assignments[DisplayIdentity(uuid: uuid)] == "ocean")
    }
}
