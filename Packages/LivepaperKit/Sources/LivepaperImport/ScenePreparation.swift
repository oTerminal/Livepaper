import Foundation
import LivepaperCore
import LivepaperScene

/// A scene's work before it can be drawn: every shader program it draws with
/// (`ProgramRequest.all(in:)`) translated to Metal once, and written beside
/// its files as `scene-programs.json` (`ScenePrograms`). The extension compiles
/// that Metal and never translates anything.
///
/// It runs where import runs, never in the extension: at import, on the staged
/// folder, and in the app for a scene in the library whose programs are
/// missing or were written by an older translator (`refresh`). A scene that
/// cannot be prepared is imported all the same, with the reason logged: the
/// extension cannot load it without programs, and holds its poster.
public enum ScenePreparation {
    public enum Outcome: Equatable, Sendable {
        /// `scene-programs.json` is written: this many programs, and this many
        /// requests that did not translate, which the scene is drawn without.
        case prepared(programs: Int, failures: Int)
        /// Nothing was written, for this reason. The scene holds its poster.
        case notPrepared(reason: String)
    }

    /// Translates every program the scene in `folder` draws with, the scene's
    /// own source of a shader first and our base material otherwise, and writes
    /// them whole into the folder, replacing what was there. Only a cancel
    /// throws: anything else is an outcome.
    public static func prepare(_ folder: URL, tools: ShaderTools?) async throws -> Outcome {
        guard let tools else { return .notPrepared(reason: "the shader tools are missing") }
        return try await onOwnThread { cancellation in
            try prepareNow(folder, translator: ShaderTranslator(tools: tools), cancellation: cancellation)
        }
    }

    /// Prepares again, one scene at a time and off the caller's actor, each
    /// scene in `wallpapers` whose folder in the library has no
    /// `scene-programs.json`, or one an older translator wrote. `log` hears each
    /// outcome as it comes. The file is replaced whole, so the extension never
    /// reads half of one. A cancel stops it where it is, leaving the scene it
    /// was on as it was.
    @concurrent
    @discardableResult
    public static func refresh(
        _ wallpapers: [Wallpaper], in location: LibraryLocation, tools: ShaderTools?,
        log: (@Sendable (Wallpaper, Outcome) async -> Void)? = nil
    ) async -> [WallpaperID: Outcome] {
        // Which scenes need it is read from their files, on a thread of its own, as all reading is.
        let needing = (try? await onOwnThread { _ in wallpapers.filter { needsPreparing($0, in: location) } }) ?? []
        var outcomes: [WallpaperID: Outcome] = [:]
        for wallpaper in needing where !Task.isCancelled {
            guard let scene = wallpaper.scene else { continue }
            let folder = location.url(for: scene.project).deletingLastPathComponent()
            guard let outcome = try? await prepare(folder, tools: tools) else { break }
            outcomes[wallpaper.id] = outcome
            await log?(wallpaper, outcome)
        }
        return outcomes
    }

    /// A scene whose programs are missing, or another translator's.
    static func needsPreparing(_ wallpaper: Wallpaper, in location: LibraryLocation) -> Bool {
        guard let scene = wallpaper.scene else { return false }
        let folder = location.url(for: scene.project).deletingLastPathComponent()
        return ScenePrograms.translator(in: folder) != ScenePrograms.currentTranslator
    }

    // MARK: The work, on a thread of its own

    static func prepareNow(_ folder: URL, translator: ShaderTranslator, cancellation: Cancellation) throws -> Outcome {
        let document: SceneDocument
        do {
            document = try SceneDocument(folder: folder)
        } catch {
            return .notPrepared(reason: "its scene cannot be read: \(error)")
        }
        var translation = Translation(files: document.files, translator: translator)
        for request in ProgramRequest.all(in: document) {
            try cancellation.check()
            do {
                try translation.add(request, cancellation: cancellation)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A tool that cannot be started or took too long, or a work folder that cannot be written: nothing is
                // known about the scene's programs, so nothing is written, and the next launch tries again.
                return .notPrepared(reason: "\(error)")
            }
        }
        let programs = translation.programs
        do {
            try programs.write(to: folder.appending(path: ScenePrograms.fileName, directoryHint: .notDirectory))
        } catch {
            return .notPrepared(reason: "\(ScenePrograms.fileName) could not be written: \(error)")
        }
        return .prepared(programs: programs.programs.count, failures: programs.failures.count)
    }

    /// The programs of one scene as they are translated, each program once
    /// however many requests share it.
    private struct Translation {
        let files: SceneFiles
        let translator: ShaderTranslator
        private(set) var programs: ScenePrograms
        /// Program key to why it did not translate, so that it is tried once.
        private var failed: [String: String] = [:]

        init(files: SceneFiles, translator: ShaderTranslator) {
            self.files = files
            self.translator = translator
            programs = ScenePrograms(translator: ScenePrograms.currentTranslator, tools: translator.tools.version)
        }

        /// Translates the request's program, or records why it could not be.
        /// Throws for a cancel, and for what is no fault of the program's: a
        /// tool that cannot be started or took too long, a work folder that
        /// cannot be written.
        mutating func add(_ request: ProgramRequest, cancellation: Cancellation) throws {
            guard let sources = Self.sources(for: request.shader, in: files) else {
                programs.failures[request.signature] = "no source for \(request.shader)"
                return
            }
            let annotations = ShaderAnnotations(sources: [sources.vertex, sources.fragment])
            let defines = annotations.defines(explicit: request.combos, boundSlots: request.boundSlots)
            let key = "\(request.shader)|" + defines.map { "\($0.name)=\($0.value)" }.joined(separator: ",")
            if let reason = failed[key] {
                programs.failures[request.signature] = reason
                return
            }
            if programs.programs[key] == nil {
                do {
                    let program = try translator.translateNow(
                        vertex: sources.vertex, fragment: sources.fragment, defines: defines, cancellation: cancellation
                    )
                    programs.programs[key] = Self.entry(request.shader, sources: sources, defines: defines, program, annotations)
                } catch let error as ShaderTranslationFailure {
                    failed[key] = error.description
                } catch let error as ShaderToolError where error.isAboutTheShader {
                    failed[key] = error.description
                }
                if let reason = failed[key] {
                    programs.failures[request.signature] = reason
                    return
                }
            }
            programs.requests[request.signature] = key
        }

        /// The scene's own source of a shader, when its package carries both stages; otherwise ours.
        static func sources(for shader: String, in files: SceneFiles) -> ShaderSources? {
            if let vertex = files.shaderSource(shader, stage: ShaderStage.vertex.rawValue),
               let fragment = files.shaderSource(shader, stage: ShaderStage.fragment.rawValue) {
                return ShaderSources(vertex: vertex, fragment: fragment, origin: "item")
            }
            return BaseMaterials.sources(for: shader)
        }

        /// A program, with where drawing finds each uniform's value and each sampler's texture when the scene sets none.
        static func entry(
            _ shader: String, sources: ShaderSources, defines: [(name: String, value: Int)], _ program: TranslatedProgram,
            _ annotations: ShaderAnnotations
        ) -> ScenePrograms.Entry {
            var uniforms: [String: ScenePrograms.UniformSource] = [:]
            var samplerDefaults: [String: String] = [:]
            for (name, uniform) in annotations.uniforms {
                if uniform.type.hasPrefix("sampler") {
                    if let slot = ShaderAnnotations.textureSlot(name), let texture = uniform.defaultValue as? String {
                        samplerDefaults[String(slot)] = texture
                    }
                } else {
                    uniforms[name] = ScenePrograms.UniformSource(materialKey: uniform.materialKey, defaultValue: uniform.defaultNumbers)
                }
            }
            return ScenePrograms.Entry(
                shader: shader, defines: Dictionary(defines.map { ($0.name, $0.value) }) { _, last in last }, origin: sources.origin,
                program: program, uniforms: uniforms, samplerDefaults: samplerDefaults
            )
        }
    }
}
