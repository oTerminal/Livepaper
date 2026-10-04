import Foundation

/// The little-endian numbers and tagged sections Wallpaper Engine's files are
/// made of, read front to back. Every read is checked against the end of the
/// data, so a file cut short or lying about a length is an error, never a crash.
struct ByteReader {
    struct CutShort: Error {}

    private let data: Data
    /// Where the next read starts, as an index into the data.
    var offset: Int

    init(_ data: Data) {
        self.data = data
        offset = data.startIndex
    }

    var isAtEnd: Bool { offset >= data.endIndex }

    /// The bytes left to read.
    var remaining: Int { max(0, data.endIndex - offset) }

    mutating func bytes(_ count: Int) throws(CutShort) -> Data {
        guard count >= 0, offset >= data.startIndex, count <= data.endIndex - offset else { throw CutShort() }
        defer { offset += count }
        return data[offset..<offset + count]
    }

    mutating func u8() throws(CutShort) -> UInt8 {
        try bytes(1).first ?? 0
    }

    mutating func u16() throws(CutShort) -> UInt16 {
        let bytes = try bytes(2)
        return bytes.reversed().reduce(0) { $0 << 8 | UInt16($1) }
    }

    mutating func u32() throws(CutShort) -> UInt32 {
        let bytes = try bytes(4)
        return bytes.reversed().reduce(0) { $0 << 8 | UInt32($1) }
    }

    mutating func i32() throws(CutShort) -> Int32 {
        Int32(bitPattern: try u32())
    }

    /// An i32, as an `Int`.
    mutating func int() throws(CutShort) -> Int {
        Int(try i32())
    }

    mutating func f32() throws(CutShort) -> Float {
        Float(bitPattern: try u32())
    }

    /// A u32 length, then that many bytes of text.
    mutating func lengthPrefixedString() throws(CutShort) -> String {
        let length = Int(try u32())
        guard let text = String(bytes: try bytes(length), encoding: .utf8) else { throw CutShort() }
        return text
    }

    /// A section's tag: eight ASCII characters and a NUL, such as `TEXV0005`.
    mutating func tag() throws(CutShort) -> String {
        let bytes = try bytes(9)
        guard bytes.last == 0, let text = String(bytes: bytes.dropLast(), encoding: .ascii) else { throw CutShort() }
        return text
    }

    /// Text up to a NUL, which is read too, of at most `max` bytes. A byte
    /// that is not UTF-8 reads as U+FFFD rather than failing the read.
    mutating func cString(max: Int = 1024) throws(CutShort) -> String {
        guard offset >= data.startIndex, offset < data.endIndex,
              let end = data[offset...].prefix(max).firstIndex(of: 0) else { throw CutShort() }
        let text = String(forgivingUTF8: data[offset..<end])
        offset = end + 1
        return text
    }

    /// Moves to the next place `marker` starts, or answers false and stays.
    mutating func seek(to marker: String) -> Bool {
        guard offset >= data.startIndex, offset <= data.endIndex,
              let found = data[offset...].firstRange(of: Data(marker.utf8)) else { return false }
        offset = found.lowerBound
        return true
    }
}
