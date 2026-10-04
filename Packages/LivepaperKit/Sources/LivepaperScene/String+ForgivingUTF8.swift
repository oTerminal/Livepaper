import Foundation

extension String {
    /// Text from bytes that should be UTF-8, read the forgiving way a scene's
    /// files need: each run of bytes that is not UTF-8 reads as U+FFFD, so a
    /// stray byte spoils one character and never the whole text, and every
    /// other byte reads as written, a byte-order mark included.
    /// `String(bytes:encoding:)` would give up on the whole text instead, and
    /// drop the mark.
    init(forgivingUTF8 bytes: some Sequence<UInt8>) {
        var scalars = String.UnicodeScalarView()
        var iterator = bytes.makeIterator()
        var decoder = UTF8()
        decoding: while true {
            switch decoder.decode(&iterator) {
            case .scalarValue(let scalar): scalars.append(scalar)
            case .error: scalars.append("\u{FFFD}")
            case .emptyInput: break decoding
            }
        }
        self.init(scalars)
    }
}
