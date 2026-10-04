import Foundation

/// The kind of file a source file is, told from its first bytes.
public enum Container: String, Equatable, Sendable, CaseIterable {
    /// MP4, M4V and QuickTime. The only kind AVFoundation opens.
    case isoMedia
    case webm
    case matroska
    case avi
    /// WMV.
    case asf
    case gif

    /// How much of the file `sniff` wants to see.
    public static let sniffLength = 64

    public static func sniff(_ head: Data) -> Container? {
        let head = Data(head.prefix(sniffLength))
        if head.count >= 8, isoBoxTypes.contains(where: { head.dropFirst(4).starts(with: $0.utf8) }) { return .isoMedia }
        if head.starts(with: [0x1A, 0x45, 0xDF, 0xA3]) { return head.contains("webm") ? .webm : .matroska }
        if head.starts(with: "RIFF".utf8) { return head.dropFirst(8).starts(with: "AVI ".utf8) ? .avi : nil }
        if head.starts(with: asfHeaderObject) { return .asf }
        if head.starts(with: "GIF87a".utf8) || head.starts(with: "GIF89a".utf8) { return .gif }
        return nil
    }

    /// The first bytes of a file on disk, as much as `sniff` wants.
    public static func sniff(contentsOf url: URL) throws -> Container? {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return sniff(try handle.read(upToCount: sniffLength) ?? Data())
    }

    // The boxes a QuickTime or MP4 file can open with. Old QuickTime movies have no `ftyp`.
    private static let isoBoxTypes = ["ftyp", "moov", "mdat", "wide", "free", "skip"]
    private static let asfHeaderObject: [UInt8] = [
        0x30, 0x26, 0xB2, 0x75, 0x8E, 0x66, 0xCF, 0x11, 0xA6, 0xD9, 0x00, 0xAA, 0x00, 0x62, 0xCE, 0x6C,
    ]
}

extension Data {
    fileprivate func contains(_ text: String) -> Bool {
        range(of: Data(text.utf8)) != nil
    }
}
