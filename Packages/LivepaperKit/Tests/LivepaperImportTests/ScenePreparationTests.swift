import Foundation
import Synchronization
import Testing
import LivepaperCore
import LivepaperImport
import LivepaperScene
import LivepaperTestSupport

/// A scene's shaders translated once, into `scene-programs.json` beside its
/// files, on scene folders the tests make.
struct ScenePreparationTests {
    let folder: TemporaryFolder

    init() throws {
        folder = try TemporaryFolder()
    }

    func programsFile(in scene: URL) -> URL {
        scene.appending(path: ScenePrograms.fileName)
    }

    /// Tools that are not there: preparing a scene that can be read gets as far as starting glslang.
    var missingTools: ShaderTools {
        ShaderTools(glslang: folder.file("gone/glslang"), spirvCross: folder.file("gone/spirv-cross"))
    }

    // MARK: With the tools

    @Test(.enabled(if: ShaderToolsHelper.shouldRun))
    func `every program the scene draws with is translated, and written with the current translator`() async throws {
        let tools = try ShaderToolsHelper.required()
        let scene = try folder.writeSceneItem("3000000001", entries: SyntheticScene.sceneWithEffect())

        let outcome = try await ScenePreparation.prepare(scene, tools: tools)

        #expect(outcome == .prepared(programs: 2, failures: 0))
        #expect(ScenePrograms.translator(in: scene) == ScenePrograms.currentTranslator)
        let programs = try ScenePrograms.read(from: programsFile(in: scene))
        #expect(programs.tools == tools.version)
        #expect(programs.failures.isEmpty)
        // Drawing asks for its programs exactly as the requests are built, and finds each.
        let requests = ProgramRequest.all(in: try SceneDocument(folder: scene))
        #expect(requests.map(\.shader) == ["genericimage2", "effects/tint"])
        for request in requests {
            #expect(programs.entry(for: request) != nil, "no program for \(request.signature)")
        }
    }

    @Test(.enabled(if: ShaderToolsHelper.shouldRun))
    func `a shader the package carries is its own; one it does not is ours`() async throws {
        let scene = try folder.writeSceneItem("3000000001", entries: SyntheticScene.sceneWithEffect())

        _ = try await ScenePreparation.prepare(scene, tools: try ShaderToolsHelper.required())

        let programs = try ScenePrograms.read(from: programsFile(in: scene))
        let image = try #require(programs.entry(for: ProgramRequest(shader: "genericimage2", combos: [:], boundSlots: [0])))
        #expect(image.origin == "builtin")
        #expect(image.program.vertex.uniforms.member("g_FrameRect") != nil, "our genericimage")
        let tint = try #require(programs.programs.values.first { $0.shader == "effects/tint" })
        #expect(tint.origin == "item")
        // The material turns SOFT on over the shader's default.
        #expect(tint.defines == ["SOFT": 1])
        #expect(tint.uniforms["g_TintColour"]?.materialKey == "colour")
        #expect(tint.uniforms["g_TintColour"]?.defaultValue == [1, 0.5, 0.25])
        #expect(tint.uniforms["g_Strength"]?.materialKey == "strength")
        #expect(tint.uniforms["g_Strength"]?.defaultValue == [0.5])
        #expect(tint.program.fragment.samplers == ["g_Texture0": 0])
    }

    @Test(.enabled(if: ShaderToolsHelper.shouldRun && GPU.device != nil))
    func `what is written compiles with Metal`() async throws {
        let device = try #require(GPU.device)
        let scene = try folder.writeSceneItem("3000000001", entries: SyntheticScene.sceneWithEffect())

        _ = try await ScenePreparation.prepare(scene, tools: try ShaderToolsHelper.required())

        let programs = try ScenePrograms.read(from: programsFile(in: scene))
        for (key, entry) in programs.programs {
            #expect(GPU.compile(entry.program.vertex.msl, on: device) == nil, "\(key) vertex")
            #expect(GPU.compile(entry.program.fragment.msl, on: device) == nil, "\(key) fragment")
        }
    }

    @Test(.enabled(if: ShaderToolsHelper.shouldRun))
    func `a program that does not translate is recorded, and the rest are written`() async throws {
        let broken = "varying vec2 v_TexCoord;\nvoid main() { gl_FragColor = undeclaredThing; }\n"
        let scene = try folder.writeSceneItem("3000000001", entries: SyntheticScene.sceneWithEffect(fragment: broken))

        let outcome = try await ScenePreparation.prepare(scene, tools: try ShaderToolsHelper.required())

        #expect(outcome == .prepared(programs: 1, failures: 1))
        let programs = try ScenePrograms.read(from: programsFile(in: scene))
        let reason = try #require(programs.failures.first { $0.key.hasPrefix("effects/tint|") }?.value)
        #expect(reason.hasPrefix("frag glslang → SPIR-V: ERROR: line "))
    }

    // MARK: Without them

    @Test func `with no tools a scene is not prepared, and nothing is written`() async throws {
        let scene = try folder.writeSceneItem("3000000001", entries: SyntheticScene.sceneWithEffect())

        let outcome = try await ScenePreparation.prepare(scene, tools: nil)

        #expect(outcome == .notPrepared(reason: "the shader tools are missing"))
        #expect(!FileManager.default.fileExists(atPath: programsFile(in: scene).path))
    }

    @Test func `tools that cannot be started leave the scene unprepared, and nothing is written`() async throws {
        let scene = try folder.writeSceneItem("3000000001", entries: SyntheticScene.sceneWithEffect())

        let outcome = try await ScenePreparation.prepare(scene, tools: missingTools)

        guard case .notPrepared(let reason) = outcome else {
            Issue.record("prepared: \(outcome)")
            return
        }
        #expect(reason.hasPrefix("glslang could not be started"))
        #expect(!FileManager.default.fileExists(atPath: programsFile(in: scene).path))
    }

    @Test func `a tool that takes too long leaves the scene unprepared, and nothing is written, so it is tried again`() async throws {
        let scene = try folder.writeSceneItem("3000000001", entries: SyntheticScene.sceneWithEffect())
        // A machine that is busy, or asleep, says nothing about the shader.
        let glslang = try folder.write("#!/bin/sh\nexec sleep 30\n", to: "tools/glslang")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: glslang.path)
        let tools = ShaderTools(glslang: glslang, spirvCross: glslang, timeLimit: .milliseconds(200))

        let outcome = try await ScenePreparation.prepare(scene, tools: tools)

        #expect(outcome == .notPrepared(reason: "glslang took too long and was stopped"))
        #expect(!FileManager.default.fileExists(atPath: programsFile(in: scene).path))
    }

    @Test func `a scene that cannot be read is not prepared`() async throws {
        let scene = try folder.writeSceneItem("3000000001", entries: [SyntheticScene.Entry("scene.json", json: "{ not JSON")])

        let outcome = try await ScenePreparation.prepare(scene, tools: missingTools)

        guard case .notPrepared(let reason) = outcome else {
            Issue.record("prepared: \(outcome)")
            return
        }
        #expect(reason.hasPrefix("its scene cannot be read"))
    }
}

/// Scenes already in the library, prepared again at launch when their programs are missing or old.
struct SceneRefreshTests {
    let bench: ImportBench

    init() throws {
        bench = try ImportBench()
    }

    func sceneWallpaper(_ number: Int, entries: [SyntheticScene.Entry], translator: Int?) throws -> Wallpaper {
        try bench.sceneWallpaper(number, entries: entries, translator: translator)
    }

    var video: Wallpaper {
        get throws { try bench.video }
    }

    func programsFile(of wallpaper: Wallpaper) throws -> URL {
        bench.location.url(for: try #require(wallpaper.scene).project).deletingLastPathComponent().appending(path: ScenePrograms.fileName)
    }

    @Test func `a scene with no programs or old ones is prepared again; a current one and a video are left alone`() async throws {
        let entries = SyntheticScene.sceneWithEffect()
        let none = try sceneWallpaper(1, entries: entries, translator: nil)
        let old = try sceneWallpaper(2, entries: entries, translator: ScenePrograms.currentTranslator - 1)
        let current = try sceneWallpaper(3, entries: entries, translator: ScenePrograms.currentTranslator)
        let currentBytes = try Data(contentsOf: programsFile(of: current))
        let heard = Mutex<[WallpaperID]>([])

        let outcomes = await ScenePreparation.refresh([none, try video, old, current], in: bench.location, tools: nil) { wallpaper, _ in
            heard.withLock { $0.append(wallpaper.id) }
        }

        let notPrepared = ScenePreparation.Outcome.notPrepared(reason: "the shader tools are missing")
        #expect(outcomes == [none.id: notPrepared, old.id: notPrepared])
        #expect(heard.withLock(\.self) == [none.id, old.id], "one at a time, in the library's order")
        #expect(try Data(contentsOf: programsFile(of: current)) == currentBytes)
    }

    @Test(.enabled(if: ShaderToolsHelper.shouldRun))
    func `a scene prepared again has programs from the current translator`() async throws {
        let entries = SyntheticScene.sceneWithEffect()
        let none = try sceneWallpaper(1, entries: entries, translator: nil)
        let old = try sceneWallpaper(2, entries: entries, translator: ScenePrograms.currentTranslator - 1)

        let outcomes = await ScenePreparation.refresh([none, old], in: bench.location, tools: try ShaderToolsHelper.required())

        #expect(outcomes == [none.id: .prepared(programs: 2, failures: 0), old.id: .prepared(programs: 2, failures: 0)])
        for wallpaper in [none, old] {
            let folder = try programsFile(of: wallpaper).deletingLastPathComponent()
            #expect(ScenePrograms.translator(in: folder) == ScenePrograms.currentTranslator)
        }
    }

    @Test func `a cancelled refresh stops where it is, and writes nothing`() async throws {
        let entries = SyntheticScene.sceneWithEffect()
        let scenes = try (1...3).map { try sceneWallpaper($0, entries: entries, translator: nil) }
        // A glslang that never finishes, so the refresh is inside the first scene when it is cancelled.
        let started = bench.home.file("started")
        let glslang = try bench.home.write("#!/bin/sh\necho $$ > '\(started.path)'\nexec sleep 30\n", to: "tools/glslang")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: glslang.path)
        let tools = ShaderTools(glslang: glslang, spirvCross: glslang)

        let refresh = Task { await ScenePreparation.refresh(scenes, in: bench.location, tools: tools) }
        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(5)
        while !FileManager.default.fileExists(atPath: started.path), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        refresh.cancel()
        let outcomes = await refresh.value

        #expect(outcomes.isEmpty)
        for scene in scenes {
            #expect(!FileManager.default.fileExists(atPath: try programsFile(of: scene).path))
        }
    }
}
