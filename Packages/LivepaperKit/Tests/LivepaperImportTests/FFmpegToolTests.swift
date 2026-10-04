import Foundation
import Testing
import LivepaperImport

/// `FFmpegTool` against stand-ins: shell scripts that behave as a helper might
/// on a bad day. The real helper is exercised by the import tests.
struct FFmpegToolTests {
    let folder: TemporaryFolder

    init() throws {
        folder = try TemporaryFolder()
    }

    /// An executable script. `$OUT` is the last argument, where ffmpeg would write.
    func helper(_ body: String, named name: String = "ffmpeg") throws -> URL {
        let script = try folder.write("#!/bin/sh\nfor OUT; do :; done\n\(body)\n", to: name)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
        return script
    }

    // MARK: Which binary

    @Test func `a replacement the user points at is preferred to the bundled helper`() throws {
        let bundled = try helper("exit 0", named: "bundled/ffmpeg")
        let replacement = try helper("exit 0", named: "mine/ffmpeg")

        #expect(FFmpegTool.locate(replacement: replacement, bundled: bundled)?.executable == replacement)
        #expect(FFmpegTool.locate(replacement: nil, bundled: bundled)?.executable == bundled)
    }

    @Test func `a replacement that is gone or cannot be run falls back to the bundled helper`() throws {
        let bundled = try helper("exit 0", named: "bundled/ffmpeg")
        let notExecutable = try folder.write("not a program", to: "mine/ffmpeg")

        #expect(FFmpegTool.locate(replacement: folder.file("gone/ffmpeg"), bundled: bundled)?.executable == bundled)
        #expect(FFmpegTool.locate(replacement: notExecutable, bundled: bundled)?.executable == bundled)
        #expect(FFmpegTool.locate(replacement: nil, bundled: nil) == nil)
    }

    // MARK: How it is run

    @Test func `the argument list is fixed: only the two paths vary`() {
        let arguments = FFmpegTool.arguments(
            source: URL(filePath: "/Users/sam/Movies/rain.webm"), destination: URL(filePath: "/tmp/staging/ffmpeg.mov")
        )

        #expect(arguments == [
            "-nostdin", "-hide_banner", "-nostats", "-loglevel", "info", "-y",
            "-protocol_whitelist", "file,pipe",
            "-i", "/Users/sam/Movies/rain.webm",
            "-map", "0:v:0", "-map", "0:a:0?", "-sn", "-dn", "-map_metadata", "-1",
            "-c:v", "hevc_videotoolbox", "-allow_sw", "1", "-tag:v", "hvc1", "-q:v", "65", "-pix_fmt", "yuv420p", "-bf", "0",
            "-fps_mode", "cfr",
            "-c:a", "aac", "-b:a", "192k",
            "-progress", "pipe:1",
            "-f", "mov", "/tmp/staging/ffmpeg.mov",
        ])
    }

    @Test func `it is given exactly that list, an empty environment and nothing to read`() async throws {
        let record = folder.file("record.txt")
        let tool = FFmpegTool(executable: try helper("""
            # The shell sets these three itself. Anything else would have come from the importer.
            { printf '%s\\n' "$@"; echo "env:"; env | grep -Ev '^(PWD|_|SHLVL)='; echo "stdin:"; cat; } > '\(record.path)'
            : > "$OUT"
            """))
        let source = try folder.write(to: "in.webm")
        let destination = folder.file("out.mov")

        try await tool.convert(source, to: destination) { _ in }

        let expected = FFmpegTool.arguments(source: source, destination: destination)
        let recorded = try String(contentsOf: record, encoding: .utf8)
        #expect(recorded == expected.joined(separator: "\n") + "\nenv:\nstdin:\n")
    }

    @Test func `progress is the time written over the duration ffmpeg announced`() async throws {
        let tool = FFmpegTool(executable: try helper("""
            echo "  Duration: 00:00:04.00, start: 0.000000, bitrate: 325 kb/s" >&2
            sleep 0.3 # ffmpeg says how long its input is well before it has written any of it
            printf 'frame=30\\nout_time_us=1000000\\nprogress=continue\\n'
            printf 'frame=90\\nout_time_us=3000000\\nprogress=continue\\n'
            : > "$OUT"
            printf 'out_time_us=4000000\\nprogress=end\\n'
            """))
        let fractions = Recorder<Double?>()

        try await tool.convert(try folder.write(to: "in.webm"), to: folder.file("out.mov")) { fractions.append($0) }

        #expect(fractions.values == [0.25, 0.75, 1])
    }

    // MARK: When it goes wrong

    @Test func `a failure carries the exit status and what ffmpeg said, and leaves no file`() async throws {
        let tool = FFmpegTool(executable: try helper(#": > "$OUT"; echo "in.webm: Invalid data found when processing input" >&2; exit 3"#))
        let output = folder.file("out.mov")

        await #expect(throws: FFmpegError.failed(status: 3, message: "in.webm: Invalid data found when processing input")) {
            try await tool.convert(try folder.write(to: "in.webm"), to: output) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test func `a helper that says it succeeded and wrote nothing has failed`() async throws {
        let tool = FFmpegTool(executable: try helper("exit 0"))

        await #expect(throws: FFmpegError.failed(status: 0, message: "no output was written")) {
            try await tool.convert(try folder.write(to: "in.webm"), to: folder.file("out.mov")) { _ in }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `it is stopped at the time limit`() async throws {
        var tool = FFmpegTool(executable: try helper(#": > "$OUT"; exec sleep 600"#))
        tool.limits.time = .milliseconds(300)
        let output = folder.file("out.mov")

        await #expect(throws: FFmpegError.timeLimitExceeded) {
            try await tool.convert(try folder.write(to: "in.webm"), to: output) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test(.timeLimit(.minutes(1)))
    func `it is stopped at the size limit, whatever the helper makes of -fs`() async throws {
        var tool = FFmpegTool(executable: try helper(#"dd if=/dev/zero of="$OUT" bs=65536 count=64 2>/dev/null; exec sleep 600"#))
        tool.limits.outputBytes = 1_000_000
        let output = folder.file("out.mov")

        await #expect(throws: FFmpegError.sizeLimitExceeded) {
            try await tool.convert(try folder.write(to: "in.webm"), to: output) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test func `a helper that finishes over the size limit has failed, however fast it was`() async throws {
        // Done and gone before the watch has looked once, and reporting success, as ffmpeg does when `-fs` cuts it short.
        var tool = FFmpegTool(executable: try helper(#"dd if=/dev/zero of="$OUT" bs=65536 count=64 2>/dev/null; exit 0"#))
        tool.limits.outputBytes = 1_000_000
        let output = folder.file("out.mov")

        await #expect(throws: FFmpegError.sizeLimitExceeded) {
            try await tool.convert(try folder.write(to: "in.webm"), to: output) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test func `what ffmpeg said last is kept, even when it said it as it died`() async throws {
        let tool = FFmpegTool(executable: try helper(#"echo "first" >&2; echo "in.webm: moov atom not found" >&2; exit 1"#))

        await #expect(throws: FFmpegError.failed(status: 1, message: "in.webm: moov atom not found")) {
            try await tool.convert(try folder.write(to: "in.webm"), to: folder.file("out.mov")) { _ in }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `a helper that ignores being asked to stop is killed`() async throws {
        var tool = FFmpegTool(executable: try helper(#"trap '' TERM; : > "$OUT"; while :; do sleep 1; done"#))
        tool.limits.time = .milliseconds(300)

        await #expect(throws: FFmpegError.timeLimitExceeded) {
            try await tool.convert(try folder.write(to: "in.webm"), to: folder.file("out.mov")) { _ in }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func `cancelling stops the helper and leaves no file`() async throws {
        let started = folder.file("started")
        let tool = FFmpegTool(executable: try helper(#": > "$OUT"; : > '\#(started.path)'; exec sleep 600"#))
        let source = try folder.write(to: "in.webm")
        let output = folder.file("out.mov")

        let conversion = Task { try await tool.convert(source, to: output) { _ in } }
        while !FileManager.default.fileExists(atPath: started.path) { try await Task.sleep(for: .milliseconds(10)) }
        conversion.cancel()

        await #expect(throws: CancellationError.self) { try await conversion.value }
        #expect(!FileManager.default.fileExists(atPath: output.path))
    }

    @Test func `a helper that cannot be started says so`() async throws {
        let tool = FFmpegTool(executable: folder.file("gone/ffmpeg"))

        await #expect(throws: FFmpegError.self) {
            try await tool.convert(try folder.write(to: "in.webm"), to: folder.file("out.mov")) { _ in }
        }
    }
}
