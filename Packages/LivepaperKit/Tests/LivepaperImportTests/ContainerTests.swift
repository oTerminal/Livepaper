import Foundation
import Testing
import LivepaperImport

struct ContainerTests {
    static func bytes(_ hex: String, then text: String = "") -> Data {
        var data = Data()
        var digits = hex.filter { !$0.isWhitespace }[...]
        while let byte = UInt8(digits.prefix(2), radix: 16), !digits.isEmpty {
            data.append(byte)
            digits = digits.dropFirst(2)
        }
        return data + Data(text.utf8)
    }

    static let rows: [Row<Data, Container?>] = [
        Row("an MP4 starts with a file-type box", bytes("00 00 00 20", then: "ftypisom"), .isoMedia),
        Row("a QuickTime movie has one too", bytes("00 00 00 14", then: "ftypqt  "), .isoMedia),
        Row("an old QuickTime movie starts straight with its movie box", bytes("00 00 0a 3c", then: "moov"), .isoMedia),
        Row("or with its media data", bytes("00 00 00 08", then: "wide"), .isoMedia),
        Row("WebM is EBML with the webm document type", bytes("1a 45 df a3 9f 42 86 81 01 42 f7 81 01 42 82 84", then: "webm"), .webm),
        Row("Matroska is EBML with its own", bytes("1a 45 df a3 a3 42 86 81 01 42 82 88", then: "matroska"), .matroska),
        Row("EBML that names neither is taken for Matroska", bytes("1a 45 df a3 9f 42 86 81 01"), .matroska),
        Row("AVI is a RIFF file of the AVI form", Data("RIFF".utf8) + bytes("24 f0 03 00", then: "AVI LIST"), .avi),
        Row("a RIFF file of another form is not", Data("RIFF".utf8) + bytes("24 f0 03 00", then: "WAVEfmt "), nil),
        Row("WMV is ASF, known by its header object", bytes("30 26 b2 75 8e 66 cf 11 a6 d9 00 aa 00 62 ce 6c"), .asf),
        Row("a GIF says so", Data("GIF89a".utf8) + bytes("a0 00 5a 00"), .gif),
        Row("and so did the older kind", Data("GIF87a".utf8), .gif),
        Row("text is nothing Livepaper reads", Data("Not a video at all, whatever the file is called.".utf8), nil),
        Row("nor is an empty file", Data(), nil),
    ]

    @Test(arguments: rows)
    func `knows a container by its first bytes, never by the file's name`(row: Row<Data, Container?>) {
        #expect(Container.sniff(row.input) == row.expected)
    }
}
