import Foundation

/// A designated requirement of the form a self-signed certificate gives (record
/// 0004): `identifier "<id>" and certificate leaf = H"<sha1>"`. The leaf is held in
/// lower case.
public struct DesignatedRequirement: Hashable, Sendable, CustomStringConvertible {
    public var identifier: String
    public var leaf: String

    public init(identifier: String, leaf: String) {
        self.identifier = identifier
        self.leaf = leaf.lowercased()
    }

    /// Reads the `designated => …` line of `codesign -d -r- <code>`'s output.
    public init(codesignOutput: String) throws(RequirementError) {
        // An ad-hoc signature's requirement is implicit, and codesign prints it commented out.
        let lines = codesignOutput.split(separator: "\n").map { $0.hasPrefix("# ") ? $0.dropFirst(2) : $0 }
        guard let line = lines.first(where: { $0.hasPrefix("designated => ") }) else { throw .unreadable }
        let requirement = line.dropFirst("designated => ".count)
        if requirement.hasPrefix("cdhash ") { throw .adHoc }
        guard let match = requirement.wholeMatch(of: #/identifier "([^"]+)" and certificate leaf = H"([0-9A-Fa-f]{40})"/#) else {
            throw .unreadable
        }
        self.init(identifier: String(match.1), leaf: String(match.2))
    }

    /// As `codesign` prints it, after `designated => `.
    public var description: String { #"identifier "\#(identifier)" and certificate leaf = H"\#(leaf)""# }
}

/// `designated-requirement.txt`: the app's and the extension's requirements, one
/// `designated => …` line each, under one certificate. `#` starts a comment.
public struct RecordedRequirements: Hashable, Sendable {
    public var requirements: [DesignatedRequirement]

    public init(file: String) throws(RequirementError) {
        var requirements: [DesignatedRequirement] = []
        for line in file.split(separator: "\n") where line.hasPrefix("designated => ") {
            requirements.append(try DesignatedRequirement(codesignOutput: String(line)))
        }
        guard !requirements.isEmpty else { throw .nothingRecorded }
        guard Set(requirements.map(\.leaf)).count == 1 else { throw .twoLeaves }
        self.requirements = requirements
    }

    /// The one certificate every requirement names.
    public var leaf: String { requirements[0].leaf }

    /// Passes only for a requirement recorded here, identifier and leaf both.
    public func check(_ actual: DesignatedRequirement) throws(RequirementError) {
        guard let recorded = requirements.first(where: { $0.identifier == actual.identifier }) else {
            throw .unrecorded(actual.identifier)
        }
        guard recorded.leaf == actual.leaf else { throw .foreignLeaf(identifier: actual.identifier, leaf: actual.leaf) }
    }

    /// Passes only for the recorded certificate, by its SHA-1 as `security` or
    /// `openssl` prints it, with or without colons, in either case.
    public func checkCertificate(sha1: String) throws(RequirementError) {
        let hash = sha1.replacingOccurrences(of: ":", with: "").lowercased()
        guard hash == leaf else { throw .unrecordedCertificate(hash) }
    }
}

public enum RequirementError: Error, Hashable, CustomStringConvertible {
    case unreadable
    /// `cdhash H"…"`: ad-hoc, a new identity every build.
    case adHoc
    case unrecorded(String)
    case foreignLeaf(identifier: String, leaf: String)
    case nothingRecorded
    case twoLeaves
    case unrecordedCertificate(String)

    public var description: String {
        switch self {
        case .unreadable: "no designated requirement of the form identifier \"…\" and certificate leaf = H\"…\""
        case .adHoc: "the signature is ad-hoc (cdhash): a release is signed with the certificate"
        case .unrecorded(let identifier): "\(identifier) has no requirement in designated-requirement.txt"
        case .foreignLeaf(let identifier, let leaf):
            "\(identifier) is signed by certificate \(leaf), not the one designated-requirement.txt records"
        case .nothingRecorded: "designated-requirement.txt records no requirement: run Tools/release/make-cert.sh once"
        case .twoLeaves: "designated-requirement.txt names two certificates"
        case .unrecordedCertificate(let hash): "the certificate \(hash) is not the one designated-requirement.txt records"
        }
    }
}
