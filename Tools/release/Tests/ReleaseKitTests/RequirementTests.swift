import ReleaseKit
import Testing

/// The designated requirement: read from `codesign -d -r-`, and held against
/// `designated-requirement.txt`, so that a release keeps the identity every
/// earlier one had.
struct RequirementTests {
    static let leaf = "67414494ac0200d42031aa6a382507f4197d3de7"
    static let otherLeaf = "0123456789abcdef0123456789abcdef01234567"

    static let recordedFile = """
        # The designated requirements of every Livepaper release. Made by
        # make-cert.sh with the certificate; a release whose signature says
        # anything else is refused.
        designated => identifier "app.livepaper.Livepaper" and certificate leaf = H"\(leaf)"
        designated => identifier "app.livepaper.Livepaper.WallpaperExtension" and certificate leaf = H"\(leaf)"

        """

    static func requirementLine(leaf: String) -> String {
        #"designated => identifier "app.livepaper.Livepaper" and certificate leaf = H"\#(leaf)""#
    }

    static func codesignOutput(_ requirement: String) -> String {
        "Executable=/Volumes/Livepaper/Livepaper.app/Contents/MacOS/Livepaper\n\(requirement)\n"
    }

    @Test func readsTheIdentifierAndTheLeafFromCodesign() throws {
        let output = Self.codesignOutput(#"designated => identifier "app.livepaper.Livepaper" and certificate leaf = H"\#(Self.leaf)""#)
        let expected = DesignatedRequirement(identifier: "app.livepaper.Livepaper", leaf: Self.leaf)
        #expect(try DesignatedRequirement(codesignOutput: output) == expected)
    }

    @Test func readsAnUppercaseLeafAsTheSameHash() throws {
        let output = Self.codesignOutput(Self.requirementLine(leaf: Self.leaf.uppercased()))
        #expect(try DesignatedRequirement(codesignOutput: output).leaf == Self.leaf)
    }

    @Test func theRecordedFileReadsAsBothRequirements() throws {
        let recorded = try RecordedRequirements(file: Self.recordedFile)
        #expect(recorded.requirements == [
            DesignatedRequirement(identifier: "app.livepaper.Livepaper", leaf: Self.leaf),
            DesignatedRequirement(identifier: "app.livepaper.Livepaper.WallpaperExtension", leaf: Self.leaf),
        ])
        #expect(recorded.leaf == Self.leaf)
    }

    @Test func theRecordedRequirementPasses() throws {
        let recorded = try RecordedRequirements(file: Self.recordedFile)
        for line in Self.recordedFile.split(separator: "\n") where line.hasPrefix("designated") {
            try recorded.check(DesignatedRequirement(codesignOutput: Self.codesignOutput(String(line))))
        }
    }

    /// As codesign prints an ad-hoc signature's, commented out, since it is implicit.
    @Test func theAdHocFormIsRefused() {
        let output = Self.codesignOutput(#"# designated => cdhash H"3684488e3a3ad60b2ef5547944f89602a811e2d5""#)
        #expect(throws: RequirementError.adHoc) { try DesignatedRequirement(codesignOutput: output) }
    }

    @Test func anotherLeafIsRefused() throws {
        let recorded = try RecordedRequirements(file: Self.recordedFile)
        let output = Self.codesignOutput(Self.requirementLine(leaf: Self.otherLeaf))
        let actual = try DesignatedRequirement(codesignOutput: output)
        #expect(throws: RequirementError.foreignLeaf(identifier: "app.livepaper.Livepaper", leaf: Self.otherLeaf)) {
            try recorded.check(actual)
        }
    }

    @Test func anIdentifierNotRecordedIsRefused() throws {
        let recorded = try RecordedRequirements(file: Self.recordedFile)
        let actual = DesignatedRequirement(identifier: "app.livepaper.Spike", leaf: Self.leaf)
        #expect(throws: RequirementError.unrecorded("app.livepaper.Spike")) { try recorded.check(actual) }
    }

    @Test func aRequirementWithMoreClausesIsRefused() {
        let output = Self.codesignOutput(
            #"designated => identifier "app.livepaper.Livepaper" and anchor apple generic and certificate leaf = H"\#(Self.leaf)""#
        )
        #expect(throws: RequirementError.unreadable) { try DesignatedRequirement(codesignOutput: output) }
    }

    @Test func noRequirementAtAllIsRefused() {
        #expect(throws: RequirementError.unreadable) { try DesignatedRequirement(codesignOutput: "code object is not signed at all\n") }
    }

    @Test func aRecordedFileWithoutRequirementsOrWithTwoLeavesIsRefused() {
        #expect(throws: RequirementError.nothingRecorded) { try RecordedRequirements(file: "# nothing yet\n") }
        let twoLeaves = """
            designated => identifier "app.livepaper.Livepaper" and certificate leaf = H"\(Self.leaf)"
            designated => identifier "app.livepaper.Livepaper.WallpaperExtension" and certificate leaf = H"\(Self.otherLeaf)"
            """
        #expect(throws: RequirementError.twoLeaves) { try RecordedRequirements(file: twoLeaves) }
    }

    @Test func theCertificatesOwnHashMatchesOnlyTheRecordedLeaf() throws {
        let recorded = try RecordedRequirements(file: Self.recordedFile)
        try recorded.checkCertificate(sha1: "67:41:44:94:AC:02:00:D4:20:31:AA:6A:38:25:07:F4:19:7D:3D:E7")
        #expect(throws: RequirementError.unrecordedCertificate(Self.otherLeaf)) { try recorded.checkCertificate(sha1: Self.otherLeaf) }
    }
}
