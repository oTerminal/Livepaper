import Foundation
import Synchronization
import Testing
import LivepaperCore
import LivepaperImport
import LivepaperTestSupport

/// A library in memory, as the app model stands behind one.
private actor MemoryLibrary: ImportLibrary {
    private(set) var library = Library()

    func wallpaper(withFingerprint fingerprint: Fingerprint) -> Wallpaper? {
        library.wallpaper(withFingerprint: fingerprint)
    }

    func wallpaper(withID id: WallpaperID) -> Wallpaper? {
        library[id]
    }

    func insert(_ wallpaper: Wallpaper) throws {
        library = try library.inserting(wallpaper)
    }
}

/// What an import's stream gave, as it gave it.
private final class Reading: Sendable {
    private struct State {
        var events: [ImportEvent] = []
        var error: (any Error)?
        var ended = false
    }

    private let state = Mutex(State())

    var events: [ImportEvent] { state.withLock { $0.events } }
    var error: (any Error)? { state.withLock { $0.error } }
    var ended: Bool { state.withLock { $0.ended } }

    /// Reads the stream on a task of its own. Cancelling the task drops the stream.
    static func start(_ stream: AsyncThrowingStream<ImportEvent, any Error>) -> (Reading, Task<Void, Never>) {
        let reading = Reading()
        let task = Task {
            do {
                for try await event in stream {
                    reading.state.withLock { $0.events.append(event) }
                }
            } catch {
                reading.state.withLock { $0.error = error }
            }
            reading.state.withLock { $0.ended = true }
        }
        return (reading, task)
    }
}

/// A fake importer on a clock that moves only when the test moves it, into a library in memory.
/// The wallpapers it makes are numbered 1, 2, 3… in the order they are made.
private final class FakeBench: Sendable {
    static let step: Duration = .seconds(1)

    let clock = ManualClock(start: Moment.launch)
    let library = MemoryLibrary()
    /// What the importer handed the wallpaper factory.
    let fingerprints = Recorder<Fingerprint>()
    let importer: FakeImporter<ManualClock>

    init() {
        let fingerprints = fingerprints
        importer = FakeImporter(library: library, clock: clock, step: Self.step) { _, fingerprint in
            fingerprints.append(fingerprint)
            return .numbered(fingerprints.values.count, fingerprint: fingerprint)
        }
    }

    /// Runs the import to its end, moving the clock a step each time the importer waits on it.
    func run(_ candidate: ImportCandidate) async -> Reading {
        let (reading, _) = Reading.start(importer.events(importing: candidate))
        while !reading.ended {
            if clock.sleeperCount > 0 { clock.advance(by: Self.step) } else { await Task.yield() }
        }
        return reading
    }

    var wallpapers: [Wallpaper] {
        get async { await library.library.wallpapers }
    }
}

private func progress(_ stage: ImportStage, _ fraction: Double? = nil) -> ImportEvent {
    .progress(ImportProgress(stage: stage, fraction: fraction))
}

/// Lets the importer's task run, without moving the clock, until `condition` holds.
private func until(_ condition: () -> Bool) async {
    while !condition() { await Task.yield() }
}

@Suite(.timeLimit(.minutes(1)))
struct FakeImporterTests {
    @Test func `walks the stages a step at a time, then imports through the library`() async throws {
        let bench = FakeBench()

        let reading = await bench.run(.numbered(1))

        #expect(Array(reading.events.dropLast()) == [
            progress(.fingerprint), progress(.probe),
            progress(.normalise, 0), progress(.normalise, 0.25), progress(.normalise, 0.5),
            progress(.normalise, 0.75), progress(.normalise, 1),
            progress(.validate), progress(.artefacts), progress(.commit),
        ])
        guard case .finished(.imported(let wallpaper, let report)) = reading.events.last else {
            Issue.record("not imported: \(reading.events.last.map(String.init(describing:)) ?? "nothing")")
            return
        }
        let fingerprint = try #require(bench.fingerprints.values.first)
        #expect(wallpaper == .numbered(1, fingerprint: fingerprint))
        #expect(await bench.wallpapers == [wallpaper])
        #expect(report.plan == .remux)
        #expect(report.seam.passes)
        #expect(bench.clock.now.offset == .seconds(9), "a step after each report but the commit's")
    }

    @Test func `the same file again is a duplicate, known before anything is converted`() async throws {
        let bench = FakeBench()
        let rain = ImportCandidate(source: URL(filePath: "/Users/tester/Movies/Rain.webm"), name: "Rain")
        guard case .finished(.imported(let first, _)) = await bench.run(rain).events.last else {
            Issue.record("the first import failed")
            return
        }

        let reading = await bench.run(ImportCandidate(source: rain.source, name: "Rain again"))

        #expect(reading.events == [progress(.fingerprint), .finished(.duplicate(of: first))])
        #expect(await bench.wallpapers == [first])
    }

    @Test func `the same file is found in the library at once, without an import or a step of the clock`() async throws {
        let bench = FakeBench()
        let rain = ImportCandidate(source: URL(filePath: "/Users/tester/Movies/Rain.webm"), name: "Rain")
        guard case .finished(.imported(let first, _)) = await bench.run(rain).events.last else {
            Issue.record("the first import failed")
            return
        }
        let before = bench.clock.now

        let again = try await bench.importer.existingWallpaper(for: ImportCandidate(source: rain.source, name: "Rain again"))
        let other = try await bench.importer.existingWallpaper(for: .numbered(1))

        #expect(again == first)
        #expect(other == nil, "a file the library does not have")
        #expect(bench.clock.now == before)
        #expect(await bench.wallpapers == [first])
    }

    @Test func `the fingerprint is the SHA-256 of the source file's path, so the file need not be there`() async {
        let bench = FakeBench()

        _ = await bench.run(.numbered(1))

        // shasum -a 256 of "/Users/tester/Movies/Harbour 1.mov".
        #expect(bench.fingerprints.values == [Fingerprint(sha256: "57f6196cfb7a98e0c107bc19ea8f648f53b97880db2ae836d5a39b05516a5beb")])
    }

    @Test func `a name with "fail" in it is rejected at the probe, and nothing is inserted`() async {
        let bench = FakeBench()
        let doomed = ImportCandidate(source: URL(filePath: "/Users/tester/Movies/Bound to Fail.mov"), name: "Bound to Fail")

        let reading = await bench.run(doomed)

        #expect(reading.events == [progress(.fingerprint), progress(.probe)])
        #expect(reading.error as? ImportError == .rejected(.unrecognised))
        #expect(await bench.wallpapers.isEmpty)
    }

    @Test func `nothing moves until its clock does, a step at a time`() async {
        let bench = FakeBench()
        let (reading, _) = Reading.start(bench.importer.events(importing: .numbered(1)))
        await until { reading.events.count == 1 && bench.clock.sleeperCount == 1 }

        bench.clock.advance(by: FakeBench.step - .nanoseconds(1))
        #expect(bench.clock.sleeperCount == 1, "still at the fingerprint")
        bench.clock.advance(by: .nanoseconds(1))
        await until { reading.events.count == 2 }

        #expect(reading.events == [progress(.fingerprint), progress(.probe)])
    }

    @Test func `dropping the stream stops the import, and nothing is inserted`() async {
        let bench = FakeBench()
        let (reading, task) = Reading.start(bench.importer.events(importing: .numbered(1)))
        await until { bench.clock.sleeperCount == 1 }
        bench.clock.advance(by: FakeBench.step)
        await until { reading.events.count == 2 && bench.clock.sleeperCount == 1 }

        task.cancel()
        await until { bench.clock.sleeperCount == 0 }
        // Were it still going, it would be through every step by now.
        bench.clock.advance(by: .seconds(3600))
        for _ in 0..<100 { await Task.yield() }

        #expect(reading.events == [progress(.fingerprint), progress(.probe)])
        #expect(bench.clock.sleeperCount == 0)
        #expect(await bench.wallpapers.isEmpty)
    }

    static let formats: [Row<String, ImportPlan>] = [
        Row("MP4 is kept as it is", "mp4", .remux),
        Row("M4V", "m4v", .remux),
        Row("QuickTime", "mov", .remux),
        Row("WebM goes through the helper first", "webm", .ffmpeg),
        Row("MKV", "mkv", .ffmpeg),
        Row("AVI", "avi", .ffmpeg),
        Row("WMV", "wmv", .ffmpeg),
        Row("GIF", "gif", .ffmpeg),
        Row("whatever the case of the extension", "WebM", .ffmpeg),
    ]

    @Test(arguments: formats)
    func `converts what only the ffmpeg helper reads, by its extension`(row: Row<String, ImportPlan>) async {
        let bench = FakeBench()

        let reading = await bench.run(ImportCandidate(source: URL(filePath: "/Users/tester/Movies/Rain.\(row.input)"), name: "Rain"))

        let converting = reading.events.filter { if case .progress(let progress) = $0 { progress.stage == .convert } else { false } }
        #expect(converting == (row.expected == .ffmpeg ? [0, 0.25, 0.5, 0.75, 1].map { progress(.convert, $0) } : []))
        guard case .finished(.imported(_, let report)) = reading.events.last else {
            Issue.record("not imported: \(reading.events.last.map(String.init(describing:)) ?? "nothing")")
            return
        }
        #expect(report.plan == row.expected)
    }
}
