import Foundation
import Testing
import LivepaperCore

/// What the `livepaper` tool prints for each reply, and how it exits.
struct CommandLineOutputTests {
    static let report = CommandLineRequestTests.report
    static let builtIn = DisplayIdentity.numbered(1)

    static let outputs: [Row<CommandReply, CommandLineOutput>] = [
        Row("done says nothing", .done(message: nil), CommandLineOutput(standardOutput: "", standardError: "", exit: .done)),
        Row(
            "done with words prints them",
            .done(message: "Studio Display now shows “Ocean”."),
            CommandLineOutput(standardOutput: "Studio Display now shows “Ocean”.\n", standardError: "", exit: .done)
        ),
        Row(
            "a refusal goes to standard error, status 1",
            .refused(reason: "No wallpaper or playlist is called “Sea”"),
            CommandLineOutput(
                standardOutput: "", standardError: "livepaper: No wallpaper or playlist is called “Sea”\n", exit: .refused
            )
        ),
        Row(
            "diagnostics as they are",
            .diagnostics("Livepaper 0.1.0 (1)\nmacOS 26.0\n"),
            CommandLineOutput(standardOutput: "Livepaper 0.1.0 (1)\nmacOS 26.0\n", standardError: "", exit: .done)
        ),
        Row(
            "diagnostics end their last line",
            .diagnostics("Livepaper 0.1.0 (1)"),
            CommandLineOutput(standardOutput: "Livepaper 0.1.0 (1)\n", standardError: "", exit: .done)
        ),
    ]

    @Test(arguments: outputs)
    func `a reply is printed, and ends the tool with a status`(row: Row<CommandReply, CommandLineOutput>) {
        #expect(CommandLineOutput(row.input, json: false) == row.expected)
    }

    @Test func `the exit statuses are the documented ones`() {
        #expect(CommandLineExit.done.rawValue == 0)
        #expect(CommandLineExit.refused.rawValue == 1)
        #expect(CommandLineExit.usage.rawValue == 2)
        #expect(CommandLineExit.unreachable.rawValue == 3)
    }

    @Test func `status prints readably`() {
        let output = CommandLineOutput(.status(Self.report), json: false)

        #expect(output.exit == .done)
        #expect(output.standardOutput == """
            Status: Live
            Pause All: off
            Mute: on

            Displays
              DDDDDDDD-0000-0000-0000-000000000001  Built-in Retina Display: wallpaper “Ocean”
              DDDDDDDD-0000-0000-0000-000000000002  Studio Display: playlist “Evening”, paused

            Wallpapers
              AAAAAAAA-0000-0000-0000-000000000001  Ocean
              AAAAAAAA-0000-0000-0000-000000000002  Forest
              AAAAAAAA-0000-0000-0000-000000000003  Caf\u{E9}
              AAAAAAAA-0000-0000-0000-000000000004  Sunset
              AAAAAAAA-0000-0000-0000-000000000005  Sunset
              AAAAAAAA-0000-0000-0000-000000000006  Evening Sky
              AAAAAAAA-0000-0000-0000-000000000007  Rain
              AAAAAAAA-0000-0000-0000-000000000008  Moon
              AAAAAAAA-0000-0000-0000-000000000009  moon

            Playlists
              BBBBBBBB-0000-0000-0000-000000000001  Evening
              BBBBBBBB-0000-0000-0000-000000000002  Rain

            """)
    }

    @Test func `an empty library and a display showing nothing print as such`() {
        let report = StatusReport(
            host: .notSelected,
            displays: [StatusReport.Display(id: Self.builtIn, name: "Built-in Retina Display", assignment: nil, isPaused: false)],
            wallpapers: [],
            playlists: [],
            isPausedAll: true,
            isMuted: false
        )

        #expect(CommandLineOutput(.status(report), json: false).standardOutput == """
            Status: Livepaper is not your wallpaper
            Pause All: on
            Mute: off

            Displays
              DDDDDDDD-0000-0000-0000-000000000001  Built-in Retina Display: nothing

            Wallpapers
              none

            Playlists
              none

            """)
    }

    @Test func `status as JSON is the report on one line`() throws {
        let output = CommandLineOutput(.status(Self.report), json: true)

        #expect(try output.standardOutput == #require(String(bytes: Self.report.encoded(), encoding: .utf8)) + "\n")
        #expect(try StatusReport.decode(Data(output.standardOutput.utf8)) == Self.report)
    }
}
