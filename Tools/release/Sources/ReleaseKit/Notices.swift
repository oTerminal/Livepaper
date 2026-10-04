import Foundation

/// What the notices name, read from the files that pin what ships: the helpers'
/// `BUILD-INFO.txt`, `Tools/release/sparkle.env`, `NOTICE`
/// and `Resources/Samples/PROVENANCE.md`. Each must be there: a gap fails rather
/// than leaving a notice out.
public struct NoticeInputs: Hashable, Sendable {
    public struct FFmpeg: Hashable, Sendable {
        public var version: String
        /// The exact source archive the helper was built from.
        public var source: String
        /// That archive's sha256, pinned in `Helpers/ffmpeg/build.sh`.
        public var sha256: String

        public init(version: String, source: String, sha256: String) {
            self.version = version
            self.source = source
            self.sha256 = sha256
        }
    }

    public struct Sample: Hashable, Sendable {
        public var file: String
        public var title: String
        public var author: String
        public var page: String
        public var licence: String

        public init(file: String, title: String, author: String, page: String, licence: String) {
            self.file = file
            self.title = title
            self.author = author
            self.page = page
            self.licence = licence
        }

        /// The wallpaper's name, as an import gives it: the file's, without `.mp4`.
        public var name: String { (file as NSString).deletingPathExtension }
    }

    public var ffmpeg: FFmpeg
    public var sparkleVersion: String
    public var glslangVersion: String
    public var spirvCrossVersion: String
    public var phospheneCommit: String
    public var samples: [Sample]
    /// The release these notices ship in, whose GitHub release carries ffmpeg's
    /// source archive.
    public var release: ReleaseVersion

    public init(
        ffmpegBuildInfo: String, shaderToolsBuildInfo: String, sparkleEnv: String, notice: String, provenance: String,
        release: ReleaseVersion
    ) throws(NoticeError) {
        self.release = release
        let ffmpegInfo = Self.fields(ffmpegBuildInfo, separator: ": ")
        let shaderInfo = Self.fields(shaderToolsBuildInfo, separator: ": ")
        ffmpeg = FFmpeg(
            version: try Self.required(ffmpegInfo["version"], "ffmpeg's version"),
            source: try Self.required(ffmpegInfo["source"], "ffmpeg's source link"),
            sha256: try Self.required(ffmpegInfo["sha256"], "ffmpeg's source sha256")
        )
        glslangVersion = try Self.required(shaderInfo["glslang"], "glslang's version")
        spirvCrossVersion = try Self.required(shaderInfo["spirv-cross"], "SPIRV-Cross's version")
        sparkleVersion = try Self.required(Self.fields(sparkleEnv, separator: "=")["SPARKLE_VERSION"], "Sparkle's version")
        let commit = notice.firstMatch(of: #/kageroumado/phosphene\s+\(commit ([0-9a-f]{7,40})/#).map { String($0.1) }
        phospheneCommit = try Self.required(commit, "Phosphene's commit")
        samples = try Self.samples(in: provenance)
        guard !samples.isEmpty else { throw .missing("the samples") }
    }

    /// `key<separator>value` lines up to the first `---` (where `BUILD-INFO.txt` goes
    /// on with what the binary prints), comments and blank lines left out.
    private static func fields(_ text: String, separator: String) -> [String: String] {
        var fields: [String: String] = [:]
        for line in text.split(separator: "\n") {
            if line.hasPrefix("---") { break }
            guard !line.hasPrefix("#"), let range = line.range(of: separator) else { continue }
            let key = String(line[..<range.lowerBound])
            if fields[key] == nil { fields[key] = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces) }
        }
        return fields
    }

    /// One sample per `## <file>.mp4` section of `PROVENANCE.md`.
    private static func samples(in provenance: String) throws(NoticeError) -> [Sample] {
        var samples: [Sample] = []
        let sections = provenance.components(separatedBy: "\n## ").dropFirst()
        for section in sections {
            let lines = section.split(separator: "\n")
            guard let file = lines.first.map(String.init), file.hasSuffix(".mp4") else { continue }
            func field(_ name: String) throws(NoticeError) -> String {
                let prefix = "- **\(name):** "
                let value = lines.first { $0.hasPrefix(prefix) }.map { String($0.dropFirst(prefix.count)) }
                return try required(value, "\(file)'s \(name.lowercased())")
            }
            samples.append(Sample(
                file: file,
                title: try field("Source title"),
                // "Free Nature Stock (see above)": the name alone.
                author: try field("Author").replacing(#/\s*\(.*\)$/#, with: ""),
                page: try field("Source page"),
                licence: try field("Licence").replacing(#/\s*\(.*\)$/#, with: "")
            ))
        }
        return samples
    }

    private static func required(_ value: String?, _ name: String) throws(NoticeError) -> String {
        guard let value, !value.trimmingCharacters(in: .whitespaces).isEmpty else { throw .missing(name) }
        return value
    }
}

public enum NoticeError: Error, Hashable, CustomStringConvertible {
    case missing(String)
    case noReadmeSection(String)

    public var description: String {
        switch self {
        case .missing(let name): "the notices cannot name \(name): it is missing from the file that pins it"
        case .noReadmeSection(let name): "README.md has no <!-- \(name): --> section"
        }
    }
}

/// The one text, and the two forms it takes besides plain text.
public enum Notices {
    /// The notices as plain text, wrapped at 80 columns: `Licenses/NOTICES.txt` on
    /// the disk image and the README's section.
    public static func text(_ inputs: NoticeInputs) -> String {
        paragraphs(inputs).map { paragraph in
            guard let paragraph else { return "" }
            let margin = String(repeating: " ", count: paragraph.indent)
            guard paragraph.wraps else { return margin + paragraph.text }
            return wrap(paragraph.text, width: 80 - paragraph.indent).map { margin + $0 }.joined(separator: "\n")
        }.joined(separator: "\n") + "\n"
    }

    /// The same paragraphs as RTF, for `Credits.rtf`, which the standard About panel
    /// shows: each one a paragraph of its own, indented as in the text and left for
    /// the panel to wrap, since the panel is narrower than 80 columns.
    public static func rtf(_ inputs: NoticeInputs) -> String {
        let body = paragraphs(inputs).map { paragraph in
            guard let paragraph else { return #"\pard\li0 \par"# }
            return #"\pard\li\#(paragraph.indent * 180) "# + rtfEscaped(paragraph.text) + #"\par"#
        }
        return ([#"{\rtf1\ansi\ansicpg1252\cocoartf2"#, #"{\fonttbl\f0\fswiss\fcharset0 Helvetica;}"#, #"\f0\fs20"#] + body + ["}"])
            .joined(separator: "\n") + "\n"
    }

    /// RTF's own characters escaped, and anything beyond ASCII as `\u` with a fallback.
    public static func rtfEscaped(_ text: String) -> String {
        var escaped = ""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\\", "{", "}": escaped += "\\\(scalar)"
            case _ where scalar.isASCII: escaped.unicodeScalars.append(scalar)
            default:
                // RTF's \u takes a signed 16-bit number and a fallback character.
                for unit in String(scalar).utf16 { escaped += "\\u\(Int16(bitPattern: unit)) ?" }
            }
        }
        return escaped
    }

    /// One paragraph of the notices: wrapped prose, or a line kept whole (a link, a
    /// hash, a command); nil is a blank line.
    private struct Paragraph {
        var indent: Int
        var text: String
        var wraps: Bool
    }

    private static func paragraphs(_ inputs: NoticeInputs) -> [Paragraph?] {
        [
            heading("Livepaper is free software under the MIT License. Copyright (c) 2026 Livepaper contributors."),
            nil,
            heading(
                "It includes, or ships beside it, the work below. The licence texts are in the Licenses folder on "
                    + "the disk image and in the source repository."
            ),
            nil,
            heading("Phosphene, commit \(inputs.phospheneCommit)"),
            line("https://github.com/kageroumado/phosphene"),
            prose("MIT License. Copyright (c) 2026 kageroumado. The wallpaper extension adapts code from it; NOTICE lists the files."),
            nil,
            heading("Sparkle \(inputs.sparkleVersion)"),
            line("https://sparkle-project.org"),
            prose("MIT License, with the notices of the code it includes. It checks for and installs Livepaper's updates."),
            nil,
        ]
            + ffmpegParagraphs(inputs.ffmpeg, release: inputs.release) + [nil]
            + shaderToolParagraphs(inputs) + [nil]
            + sampleParagraphs(inputs.samples)
    }

    /// The LGPL's notice: the version, the exact source and its sha256,
    /// where the source is published, and how to run another build instead.
    private static func ffmpegParagraphs(_ ffmpeg: NoticeInputs.FFmpeg, release: ReleaseVersion) -> [Paragraph?] {
        let archive = ffmpeg.source.split(separator: "/").last.map(String.init) ?? ffmpeg.source
        return [
            heading("ffmpeg \(ffmpeg.version), the import helper"),
            line("https://ffmpeg.org"),
            prose(
                "GNU Lesser General Public License, version 2.1 or later. A separate program, "
                    + "Livepaper.app/Contents/MacOS/ffmpeg, that converts WebM, MKV, AVI, WMV and GIF files at import. "
                    + "Built without GPL or non-free parts and without network support, from this source archive:"
            ),
            line(ffmpeg.source, indent: 4),
            line("sha256 \(ffmpeg.sha256)", indent: 4),
            prose("This release of Livepaper carries a copy of that archive, with the build script and the configure line:"),
            line("https://github.com/oTerminal/Livepaper/releases/download/\(release.tag)/\(archive)", indent: 4),
            prose("To run your own ffmpeg build instead of this one:"),
            line("defaults write app.livepaper.Livepaper FFmpegReplacement /path/to/ffmpeg", indent: 4),
            prose("and to go back to this one:"),
            line("defaults delete app.livepaper.Livepaper FFmpegReplacement", indent: 4),
        ]
    }

    /// glslang and SPIRV-Cross.
    private static func shaderToolParagraphs(_ inputs: NoticeInputs) -> [Paragraph?] {
        [
            heading("glslang \(inputs.glslangVersion), a shader tool"),
            line("https://github.com/KhronosGroup/glslang"),
            prose(
                "BSD-3-Clause, with BSD-2-Clause, Apache-2.0 and MIT for some files, NVIDIA's licence for the "
                    + "preprocessor, and GPL-3.0-or-later with the Bison exception 2.2 for its generated parser. "
                    + "A separate program that translates a scene's shaders at import."
            ),
            nil,
            heading("SPIRV-Cross \(inputs.spirvCrossVersion), a shader tool"),
            line("https://github.com/KhronosGroup/SPIRV-Cross"),
            prose(
                "Apache-2.0; the SPIR-V headers it compiles in are MIT and Khronos's free-use licence. "
                    + "A separate program that translates a scene's shaders at import."
            ),
        ]
    }

    /// The samples' CC0 provenance (`PROVENANCE.md`).
    private static func sampleParagraphs(_ samples: [NoticeInputs.Sample]) -> [Paragraph?] {
        var paragraphs: [Paragraph?] = [heading("The sample wallpapers")]
        for sample in samples {
            paragraphs.append(prose("\(sample.name): \"\(sample.title)\" by \(sample.author), \(sample.licence)"))
            paragraphs.append(line(sample.page, indent: 4))
        }
        paragraphs.append(prose(
            "Cut from the videos above. CC0 1.0 is a public-domain dedication: https://creativecommons.org/publicdomain/zero/1.0/"
        ))
        return paragraphs
    }

    private static func heading(_ text: String) -> Paragraph { Paragraph(indent: 0, text: text, wraps: true) }
    private static func prose(_ text: String) -> Paragraph { Paragraph(indent: 2, text: text, wraps: true) }
    private static func line(_ text: String, indent: Int = 2) -> Paragraph { Paragraph(indent: indent, text: text, wraps: false) }

    /// Words filled into lines of at most `width`; a word longer than that has a line of its own.
    private static func wrap(_ text: String, width: Int) -> [String] {
        var lines: [String] = []
        var current = ""
        for word in text.split(separator: " ") {
            if current.isEmpty {
                current = String(word)
            } else if current.count + 1 + word.count <= width {
                current += " " + word
            } else {
                lines.append(current)
                current = String(word)
            }
        }
        if !current.isEmpty { lines.append(current) }
        return lines
    }

    /// The README with one of its generated sections (a `text` block between the
    /// `<!-- <name>: … -->` and `<!-- /<name> -->` lines) holding this text: `notices`,
    /// or `requirement`, from `designated-requirement.txt`.
    public static func readme(_ readme: String, section name: String, carrying text: String) throws(NoticeError) -> String {
        let parts = try ReadmeSection(readme, name: name)
        return parts.before + "```text\n" + text.trimmingCharacters(in: .newlines) + "\n```\n" + parts.after
    }

    /// The text one of the README's generated sections holds now.
    public static func readmeText(_ readme: String, section name: String) throws(NoticeError) -> String {
        let lines = try ReadmeSection(readme, name: name).inside.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first == "```text", let close = lines.lastIndex(of: "```") else { throw .noReadmeSection(name) }
        return lines[1..<close].joined(separator: "\n")
    }

    /// A README split around one generated section's contents.
    private struct ReadmeSection {
        var before: String
        var inside: String
        var after: String

        init(_ readme: String, name: String) throws(NoticeError) {
            guard
                let start = readme.range(of: "<!-- \(name):"),
                let startLineEnd = readme[start.upperBound...].firstIndex(of: "\n"),
                let end = readme.range(of: "<!-- /\(name) -->", range: startLineEnd..<readme.endIndex)
            else { throw .noReadmeSection(name) }
            let contentStart = readme.index(after: startLineEnd)
            before = String(readme[..<contentStart])
            inside = String(readme[contentStart..<end.lowerBound])
            after = String(readme[end.lowerBound...])
        }
    }
}
