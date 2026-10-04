import CoreMedia
import Testing
@testable import LivepaperPlayback

// Times are ticks of 1/15360 s, the timescale of the spike's clips, where a frame at 30 fps is 512 ticks.
private let timescale: CMTimeScale = 15360
private let frame: Int64 = 512

private func ticks(_ value: Int64) -> CMTime {
    CMTime(value: value, timescale: timescale)
}

/// A buffer that carries one frame, as the reader vends it.
private func picture(media: Int64, output: Int64, decode: Int64?, duration: Int64? = frame) -> VendedBuffer {
    VendedBuffer(
        sampleCount: 1,
        hasDataBuffer: true,
        presentationTime: ticks(media),
        outputPresentationTime: ticks(output),
        decodeTime: decode.map(ticks) ?? .invalid,
        duration: duration.map(ticks) ?? .invalid
    )
}

/// A file of `count` frames in order, with no edit list.
private func plainPass(count: Int64) -> [VendedBuffer] {
    (0 ..< count).map { picture(media: $0 * frame, output: $0 * frame, decode: $0 * frame) }
}

extension PassLedger {
    /// Stamps every buffer of one pass and ends it.
    fileprivate mutating func play(_ pass: [VendedBuffer]) -> [FrameStamp?] {
        defer { finishPass() }
        return pass.map { stamp($0) }
    }
}

struct PassLedgerTests {
    @Test func `a first frame at media time 0.0667 with an edit list to 0 is stamped at 0`() {
        var ledger = PassLedger(frameDuration: ticks(frame))

        let stamp = ledger.stamp(picture(media: 1024, output: 0, decode: 0))

        #expect(stamp?.presentationTime == ticks(0))
        // The decode time moves with it, so it stays two frames ahead of presentation.
        #expect(stamp?.decodeTime == ticks(-1024))
    }

    @Test func `the next pass starts where the last frame of this one ends`() {
        var ledger = PassLedger(frameDuration: ticks(frame))
        _ = ledger.play(plainPass(count: 150))

        let first = ledger.stamp(picture(media: 0, output: 0, decode: 0))

        #expect(ledger.offset == ticks(150 * frame))
        #expect(first?.presentationTime == ticks(150 * frame))
        #expect(first?.decodeTime == ticks(150 * frame))
    }

    @Test func `the seam step is one frame duration`() {
        var ledger = PassLedger(frameDuration: ticks(frame))

        for _ in 0 ..< 3 { _ = ledger.play(plainPass(count: 150)) }

        #expect(ledger.loops == 3)
        #expect(ledger.largestSeamStep == 1)
        #expect(ledger.largestInLoopStep == 1)
    }

    // ffmpeg's B-frames: frames shown 0 to 5 are decoded in the order 0 3 1 2 5 4, and sit two
    // frames late in media time, which the edit list takes back.
    static let reordered: [VendedBuffer] = [0, 3, 1, 2, 5, 4].enumerated().map { decodeIndex, shown in
        picture(media: (Int64(shown) + 2) * frame, output: Int64(shown) * frame, decode: Int64(decodeIndex) * frame)
    }

    @Test func `with B-frames the pass ends at the latest frame, not the last one vended`() {
        var ledger = PassLedger(frameDuration: ticks(frame))

        let stamps = ledger.play(Self.reordered)

        #expect(stamps.compactMap { $0?.presentationTime } == [0, 3, 1, 2, 5, 4].map { ticks($0 * frame) })
        #expect(ledger.enqueuedUntil == ticks(6 * frame))
        #expect(ledger.offset == ticks(6 * frame))
    }

    @Test func `with B-frames and an edit list every pass is on one timeline`() {
        var ledger = PassLedger(frameDuration: ticks(frame))

        let first = ledger.play(Self.reordered)
        let second = ledger.play(Self.reordered)

        #expect(first.first??.presentationTime == ticks(0))
        #expect(second.first??.presentationTime == ticks(6 * frame))
        #expect(second.first??.decodeTime == ticks(4 * frame))
        #expect(ledger.largestSeamStep == 1)
        #expect(ledger.largestInLoopStep == 1)
    }

    static let markers: [Row<VendedBuffer, Void>] = [
        Row(
            "the edit boundary before the first frame",
            VendedBuffer(
                sampleCount: 0, hasDataBuffer: false, presentationTime: ticks(0),
                outputPresentationTime: ticks(0), decodeTime: .invalid, duration: .invalid
            ),
            ()
        ),
        Row(
            "the empty-media marker at the track's duration",
            VendedBuffer(
                sampleCount: 0, hasDataBuffer: false, presentationTime: CMTime(value: 5000, timescale: 1000),
                outputPresentationTime: CMTime(value: 5000, timescale: 1000), decodeTime: .invalid, duration: .invalid
            ),
            ()
        ),
        Row(
            "a drain marker with no time",
            VendedBuffer(
                sampleCount: 0, hasDataBuffer: false, presentationTime: .invalid,
                outputPresentationTime: .invalid, decodeTime: .invalid, duration: .invalid
            ),
            ()
        ),
        Row(
            "a sample count with no data behind it",
            VendedBuffer(
                sampleCount: 1, hasDataBuffer: false, presentationTime: ticks(0),
                outputPresentationTime: ticks(0), decodeTime: ticks(0), duration: ticks(frame)
            ),
            ()
        ),
    ]

    @Test(arguments: markers)
    func `a buffer without media is not a frame`(row: Row<VendedBuffer, Void>) {
        var ledger = PassLedger(frameDuration: ticks(frame))
        _ = ledger.play(plainPass(count: 150).dropLast())

        let stamp = ledger.stamp(row.input)

        #expect(stamp == nil)
        #expect(ledger.markersSkipped == 1)
        #expect(ledger.enqueuedUntil == ticks(149 * frame))
    }

    @Test func `the marker at the track's duration does not make the pass a frame longer`() {
        var ledger = PassLedger(frameDuration: ticks(frame))
        let end = VendedBuffer(
            sampleCount: 0, hasDataBuffer: false, presentationTime: ticks(150 * frame),
            outputPresentationTime: ticks(150 * frame), decodeTime: .invalid, duration: .invalid
        )

        _ = ledger.play(plainPass(count: 150) + [end])

        #expect(ledger.offset == ticks(150 * frame))
    }

    @Test func `only the first pass keeps the reader's decoder reset`() {
        var ledger = PassLedger(frameDuration: ticks(frame))

        let first = ledger.play(plainPass(count: 3))
        let second = ledger.play(plainPass(count: 3))

        #expect(first.map { $0?.dropsDecoderReset } == [false, false, false])
        #expect(second.map { $0?.dropsDecoderReset } == [true, true, true])
    }

    @Test func `only the first frame of a later pass opens a seam`() {
        var ledger = PassLedger(frameDuration: ticks(frame))

        let first = ledger.play(plainPass(count: 3))
        let second = ledger.play(plainPass(count: 3))

        #expect(first.map { $0?.opensSeam } == [false, false, false])
        #expect(second.map { $0?.opensSeam } == [true, false, false])
    }

    @Test func `a frame with no duration lasts one frame duration`() {
        var ledger = PassLedger(frameDuration: ticks(frame))

        _ = ledger.play([picture(media: 0, output: 0, decode: 0, duration: nil)])

        #expect(ledger.offset == ticks(frame))
    }

    @Test func `a frame with no decode time is stamped with none`() {
        var ledger = PassLedger(frameDuration: ticks(frame))

        let stamp = ledger.stamp(picture(media: 0, output: 0, decode: nil))

        #expect(stamp?.decodeTime.isValid == false)
    }

    @Test func `a missing frame shows as an in-loop step of two`() {
        var ledger = PassLedger(frameDuration: ticks(frame))
        var pass = plainPass(count: 10)
        pass.remove(at: 5)

        _ = ledger.play(pass)

        #expect(ledger.largestInLoopStep == 2)
    }

    @Test func `a pass with no frames changes nothing`() {
        var ledger = PassLedger(frameDuration: ticks(frame))
        _ = ledger.play(plainPass(count: 150))

        ledger.finishPass()

        #expect(ledger.loops == 1)
        #expect(ledger.offset == ticks(150 * frame))
    }
}
