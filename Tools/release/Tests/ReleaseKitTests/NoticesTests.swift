import Foundation
import ReleaseKit
import Testing

/// The notices: one text, made from the files that pin what ships, put in
/// `Licenses/` on the disk image, the About panel's `Credits.rtf` and the README.
struct NoticesTests {
    static let ffmpegBuildInfo = """
        ffmpeg helper for Livepaper, built by Helpers/ffmpeg/build.sh
        version: 9.0.2
        source: https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz
        sha256: 8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e
        binary-sha256: 743f3466b325864b79eb0aceebaed6fea4d85a54313a4d3bce5dcc7aa4943ac2

        --- ffmpeg -version
        version: not this one
        """

    static let shaderToolsBuildInfo = """
        Shader tools for Livepaper, built by Helpers/shader-tools/build.sh
        glslang: 16.6.0
        glslang-source: https://github.com/KhronosGroup/glslang/archive/refs/tags/16.6.0.tar.gz
        glslang-sha256: 9c09b901149c729df745057dafa815278aaa101b84d2b6e14f16a42de52f97f2
        spirv-cross: vulkan-sdk-1.4.357.0
        spirv-cross-source: https://github.com/KhronosGroup/SPIRV-Cross/archive/refs/tags/vulkan-sdk-1.4.357.0.tar.gz
        spirv-cross-sha256: 97c910326afdd44d794ce8561326fa675fd1958b27142f03295403044d639639
        """

    static let notice = """
        Livepaper includes code adapted from Phosphene
          https://github.com/kageroumado/phosphene  (commit 8b5bd57, 2026-09-03)

        Copyright (c) 2026 kageroumado
        """

    static let provenance = """
        # Sample wallpapers: provenance

        ## Licence

        Free Nature Stock's licence page says CC0.

        ## Autumn Stream.mp4

        - **Source title:** Autumn Leaves in River Water
        - **Author:** Free Nature Stock (see above)
        - **Source page:** https://freenaturestock.com/video/autumn-leaves-in-river-water/
        - **Licence:** CC0 1.0 (https://freenaturestock.com/license/)

        ## Golden Maple.mp4

        - **Source title:** Clouds Above a Maple Tree
        - **Author:** Free Nature Stock (see above)
        - **Source page:** https://freenaturestock.com/video/clouds-above-a-maple-tree/
        - **Licence:** CC0 1.0 (https://freenaturestock.com/license/)

        ## How the loops are made seamless

        Not a sample.
        """

    static func inputs() throws -> NoticeInputs {
        try NoticeInputs(
            ffmpegBuildInfo: ffmpegBuildInfo,
            shaderToolsBuildInfo: shaderToolsBuildInfo,
            sparkleEnv: "# Sparkle's tools\nSPARKLE_VERSION=2.10.0\nSPARKLE_SHA256=abc\n",
            notice: notice,
            provenance: provenance,
            release: ReleaseVersion(marketing: "1.0.0", build: 12)
        )
    }

    @Test func readsWhatShipsFromTheFilesThatPinIt() throws {
        let inputs = try Self.inputs()
        #expect(inputs.ffmpeg == NoticeInputs.FFmpeg(
            version: "9.0.2",
            source: "https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz",
            sha256: "8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e"
        ))
        #expect(inputs.sparkleVersion == "2.10.0")
        #expect(inputs.glslangVersion == "16.6.0")
        #expect(inputs.spirvCrossVersion == "vulkan-sdk-1.4.357.0")
        #expect(inputs.phospheneCommit == "8b5bd57")
        #expect(inputs.samples == [
            NoticeInputs.Sample(
                file: "Autumn Stream.mp4", title: "Autumn Leaves in River Water", author: "Free Nature Stock",
                page: "https://freenaturestock.com/video/autumn-leaves-in-river-water/", licence: "CC0 1.0"
            ),
            NoticeInputs.Sample(
                file: "Golden Maple.mp4", title: "Clouds Above a Maple Tree", author: "Free Nature Stock",
                page: "https://freenaturestock.com/video/clouds-above-a-maple-tree/", licence: "CC0 1.0"
            ),
        ])
    }

    @Test func theTextNamesEverythingThatShips() throws {
        let text = try Notices.text(Self.inputs())
        for name in [
            "ffmpeg 9.0.2", "https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz",
            "8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e",
            "FFmpegReplacement", "GNU Lesser General Public License",
            "https://github.com/oTerminal/Livepaper/releases/download/v1.0.0/ffmpeg-9.0.2.tar.xz",
            "Sparkle 2.10.0", "Phosphene", "8b5bd57",
            "glslang 16.6.0", "SPIRV-Cross vulkan-sdk-1.4.357.0",
            "Autumn Stream", "Autumn Leaves in River Water", "https://freenaturestock.com/video/autumn-leaves-in-river-water/",
            "Golden Maple", "Clouds Above a Maple Tree", "CC0 1.0", "MIT License",
        ] {
            #expect(text.contains(name), "the notices do not name \(name)")
        }
        #expect(!text.contains("binary-sha256"))
        #expect(!text.contains("not this one"))
    }

    /// Each row takes one line out of the file that pins it.
    static let gaps: [Row<(file: String, line: String), NoticeError>] = [
        Row("no ffmpeg version", ("ffmpeg", "version: 9.0.2"), .missing("ffmpeg's version")),
        Row(
            "no ffmpeg source link",
            ("ffmpeg", "source: https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz"), .missing("ffmpeg's source link")
        ),
        Row(
            "no ffmpeg source sha256",
            ("ffmpeg", "sha256: 8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e"), .missing("ffmpeg's source sha256")
        ),
        Row("no glslang version", ("shader-tools", "glslang: 16.6.0"), .missing("glslang's version")),
        Row("no SPIRV-Cross version", ("shader-tools", "spirv-cross: vulkan-sdk-1.4.357.0"), .missing("SPIRV-Cross's version")),
        Row("no Sparkle version", ("sparkle", "SPARKLE_VERSION=2.10.0"), .missing("Sparkle's version")),
        Row(
            "no Phosphene commit",
            ("notice", "  https://github.com/kageroumado/phosphene  (commit 8b5bd57, 2026-09-03)"), .missing("Phosphene's commit")
        ),
        Row("no samples", ("provenance", "## Autumn Stream.mp4"), .missing("the samples")),
    ]

    @Test(arguments: gaps)
    func aGapFails(_ row: Row<(file: String, line: String), NoticeError>) {
        func pinned(_ file: String, _ text: String) -> String {
            guard file == row.input.file else { return text }
            if file == "provenance" { return String(text[..<text.range(of: row.input.line)!.lowerBound]) }
            #expect(text.contains(row.input.line))
            return text.replacingOccurrences(of: row.input.line + "\n", with: "")
        }
        #expect(throws: row.expected) {
            try NoticeInputs(
                ffmpegBuildInfo: pinned("ffmpeg", Self.ffmpegBuildInfo),
                shaderToolsBuildInfo: pinned("shader-tools", Self.shaderToolsBuildInfo),
                sparkleEnv: pinned("sparkle", "SPARKLE_VERSION=2.10.0\n"),
                notice: pinned("notice", Self.notice),
                provenance: pinned("provenance", Self.provenance),
                release: ReleaseVersion(marketing: "1.0.0", build: 12)
            )
        }
    }

    @Test func aSampleWithoutItsSourceFails() {
        let page = "- **Source page:** https://freenaturestock.com/video/clouds-above-a-maple-tree/\n"
        let gap = Self.provenance.replacingOccurrences(of: page, with: "")
        #expect(throws: NoticeError.missing("Golden Maple.mp4's source page")) {
            try NoticeInputs(
                ffmpegBuildInfo: Self.ffmpegBuildInfo, shaderToolsBuildInfo: Self.shaderToolsBuildInfo,
                sparkleEnv: "SPARKLE_VERSION=2.10.0", notice: Self.notice, provenance: gap,
                release: ReleaseVersion(marketing: "1.0.0", build: 12)
            )
        }
    }

    @Test func theTextIsWrappedAtEightyColumns() throws {
        let text = Notices.text(try Self.inputs())
        for line in text.split(separator: "\n") where !line.contains("://") && !line.contains("sha256") {
            #expect(line.count <= 80, "\(line)")
        }
        #expect(text.contains("\n    https://ffmpeg.org/releases/ffmpeg-9.0.2.tar.xz\n"))
    }

    /// The About panel is narrower than the text, so each paragraph is one RTF
    /// paragraph there, indented as in the text: the same words, unwrapped.
    @Test func theAboutPanelsCreditsAreTheSameWordsAsTheText() throws {
        let inputs = try Self.inputs()
        let rtf = Notices.rtf(inputs)
        #expect(rtf.hasPrefix(#"{\rtf1\ansi\ansicpg1252"#))
        #expect(rtf.hasSuffix("}\n"))
        #expect(rtf.contains("\\pard\\li360 "))
        func words(_ text: String) -> [Substring] { text.split(whereSeparator: \.isWhitespace) }
        let body = rtf.split(separator: "\n").filter { $0.hasPrefix("\\pard") }
            .map { $0.replacing(#/^\\pard(\\li\d+)?(\\b)? /#, with: "").replacing(#/\\b0 /#, with: "").replacing(#/\\par$/#, with: "") }
            .joined(separator: " ")
        #expect(words(body) == words(Notices.text(inputs)))
    }

    @Test func rtfEscapesItsOwnCharactersAndWritesOthersAsUnicode() {
        #expect(Notices.rtfEscaped("Livepaper {MIT} café \\ done") == #"Livepaper \{MIT\} caf\u233 ? \\ done"#)
    }

    static let readme = """
        # Livepaper

        ## Licences

        <!-- notices: made by `make notices` from what ships; edit Tools/release, not this -->
        ```text
        old text
        ```
        <!-- /notices -->

        ## Contributing
        """

    @Test func theReadmeCarriesTheTextBetweenItsMarkers() throws {
        let updated = try Notices.readme(Self.readme, section: "notices", carrying: "new text\nline two")
        #expect(updated == Self.readme.replacingOccurrences(of: "old text", with: "new text\nline two"))
        #expect(try Notices.readmeText(updated, section: "notices") == "new text\nline two")
        #expect(throws: NoticeError.noReadmeSection("requirement")) { try Notices.readmeText(updated, section: "requirement") }
    }

    @Test func aReadmeWithoutTheMarkersFails() {
        #expect(throws: NoticeError.noReadmeSection("notices")) {
            try Notices.readme("# Livepaper\n", section: "notices", carrying: "text")
        }
        #expect(throws: NoticeError.noReadmeSection("notices")) { try Notices.readmeText("# Livepaper\n", section: "notices") }
    }
}
