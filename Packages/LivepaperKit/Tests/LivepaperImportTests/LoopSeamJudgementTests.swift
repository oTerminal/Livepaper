import Foundation
import Testing
import LivepaperImport

/// Worked by hand in ticks of a 15360 timescale, where a 30 fps frame is 512 ticks.
struct LoopSeamJudgementTests {
    /// A clean four-frame track: frames at 0, 512, 1024, 1536, track 2048 long, no edit list.
    static func clean() -> TrackReading {
        TrackReading(
            timescale: 15360,
            frames: (0..<4).map { TrackReading.Frame(pts: Int64($0) * 512, duration: 512, isSync: $0 == 0) },
            trackDuration: 2048,
            hasEditList: false
        )
    }

    static func changed(_ change: (inout TrackReading) -> Void) -> TrackReading {
        var reading = clean()
        change(&reading)
        return reading
    }

    @Test func `a clean track passes, and the report carries the numbers`() {
        let report = judgeLoopSeam(Self.clean())

        #expect(report.passes)
        #expect(report.frameCount == 4)
        #expect(report.firstPTS == 0)
        #expect(report.frameDuration == 512)
        #expect(report.largestStepError == 0)
        #expect(report.endOfLastFrame == 2048)
        #expect(report.trackDuration == 2048)
        #expect(report.seamStep == 512)
        #expect(report.framesBeforeFirstSync == 0)
    }

    static let rows: [Row<TrackReading, [LoopSeamFailure]>] = [
        Row("no frames at all", changed { $0.frames = [] }, [.noFrames]),
        Row(
            // Seam step 1024 + 3072 − 2560 = 1536: the last picture held for three frames, as the spike saw.
            "the first frame is not at zero: ffmpeg's B-frame offset, two frames in",
            changed { reading in
                reading.frames = reading.frames.map { TrackReading.Frame(pts: $0.pts + 1024, duration: 512, isSync: $0.isSync) }
                reading.trackDuration = 3072
            },
            [.firstFrameNotAtZero, .seamStepNotOneFrame]
        ),
        Row("the first frame is not a sync sample", changed { $0.frames[0].isSync = false }, [.firstFrameNotSync, .framesBeforeFirstSync]),
        Row("one tick of rounding between frames is allowed", changed { $0.frames[2].pts = 1025 }, []),
        Row("two ticks is an uneven frame", changed { $0.frames[2].pts = 1026 }, [.unevenFrames]),
        Row(
            "a dropped frame in a variable-rate file",
            changed { reading in
                reading.frames.remove(at: 2)
            },
            [.unevenFrames]
        ),
        Row(
            "frames are compared in presentation order, so reordered B-frames are even",
            changed { reading in
                reading.frames = [0, 1536, 512, 1024].map { TrackReading.Frame(pts: $0, duration: 512, isSync: $0 == 0) }
            },
            []
        ),
        Row(
            "the track is longer than its frames: the picture would hold at the seam",
            changed { $0.trackDuration = 2048 + 614 },
            [.trackDurationNotEndOfLastFrame, .seamStepNotOneFrame]
        ),
        Row(
            "the last frame is longer than the rest, and the track with it",
            changed { reading in
                reading.frames[3].duration = 1024
                reading.trackDuration = 2560
            },
            [.seamStepNotOneFrame]
        ),
        Row("the track one tick longer than its frames: its duration has to be exact", changed { $0.trackDuration = 2049 }, [
            .trackDurationNotEndOfLastFrame,
        ]),
        Row("an edit list", changed { $0.hasEditList = true }, [.editList]),
        Row("an open first GOP", openFirstGOP, [.firstFrameNotSync, .framesBeforeFirstSync]),
    ]

    /// A leading picture: decoded after the sync sample, shown before it, predicted from a GOP that is not there.
    static let openFirstGOP = changed { reading in
        reading.frames = [
            TrackReading.Frame(pts: 512, duration: 512, isSync: true),
            TrackReading.Frame(pts: 0, duration: 512, isSync: false),
            TrackReading.Frame(pts: 1024, duration: 512, isSync: false),
            TrackReading.Frame(pts: 1536, duration: 512, isSync: false),
        ]
    }

    @Test(arguments: rows)
    func `says what is wrong with a track`(row: Row<TrackReading, [LoopSeamFailure]>) {
        let report = judgeLoopSeam(row.input)

        #expect(report.failures == row.expected)
    }

    @Test func `a failing report still carries the numbers, so the import can say what was wrong`() {
        let report = judgeLoopSeam(Self.changed { $0.trackDuration = 2662 })

        #expect(report.endOfLastFrame == 2048)
        #expect(report.trackDuration == 2662)
        #expect(report.seamStep == 1126)
        #expect(report.description.contains("seam step 1126"))
    }

    @Test func `a leading picture is counted`() {
        #expect(judgeLoopSeam(Self.openFirstGOP).framesBeforeFirstSync == 1)
    }
}
