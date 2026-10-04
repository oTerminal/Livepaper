// Ported from the spike's renderer,
// written from scratch for this project. What each of Wallpaper Engine's names means is inferred
// from the samples' own files, not from Wallpaper Engine.

import Foundation
import Metal
import simd

/// Draws a Wallpaper Engine scene from its folder in the library.
///
/// Loading reads the scene (`SceneDocument`), uploads its textures and our
/// stand-ins for Wallpaper Engine's own, reads its puppets and particle
/// systems, and compiles the programs its import translated
/// (`scene-programs.json`); a scene without them cannot be drawn, and its
/// surface holds its poster, still. Drawing computes every picture from the
/// scene time, so a scene never loops: layers in the scene's order, each with
/// its effects, particles simulated up to that time, then the scene's bloom,
/// into the surface's drawable. Nothing is baked, nothing waits for the GPU.
public final class WallpaperEngineScene: SceneDrawing {
    public enum LoadError: LocalizedError, Equatable, Sendable {
        /// The scene has no translated programs yet, or they do not read.
        case noPrograms(URL)
        /// It has programs, but not one of them compiles here.
        case noProgramCompiles

        public var errorDescription: String? {
            switch self {
            case .noPrograms(let file): "it has no programs (\(file.lastPathComponent)): the app prepares them"
            case .noProgramCompiles: "none of its programs compiles"
            }
        }
    }

    public let document: SceneDocument
    /// What could not be drawn as the scene asks, or was stood in for, once each: for the log.
    public var notes: [String] { noteList + textures.notes + programs.failures.map { "program \($0)" } }

    let device: any MTLDevice
    let textures: SceneTextureStore
    let programs: CompiledPrograms
    let passes: BasePasses
    /// A quad over clip space as a strip of four: position, then UV from the top left.
    let quad: any MTLBuffer

    var width = 0
    var height = 0
    var projection = matrix_identity_float4x4
    /// Output pixels per scene unit.
    var pixelsPerUnit: Float = 1
    var sceneColour: (any MTLTexture)?
    /// Render targets by name, kept while the output's size stays, so effects with history keep it.
    var targets: [String: any MTLTexture] = [:]
    var particleGroups: [Int: ParticleGroup] = [:]
    var puppets: [Int: PuppetMesh] = [:]
    /// Where the pointer is, 0 to 1 from the top left of the display, and where the scene sees it,
    /// following it by the scene's parallax delay.
    private var pointerTarget = SIMD2<Float>(0.5, 0.5)
    private(set) var pointer = SIMD2<Float>(0.5, 0.5)
    private var lastTime: Float?
    private var noteList: [String] = []
    private var noted = Set<String>()

    public convenience init(folder: URL, device: any MTLDevice) throws {
        let file = folder.appending(path: ScenePrograms.fileName, directoryHint: .notDirectory)
        let manifest: ScenePrograms
        do {
            manifest = try ScenePrograms.read(from: file)
        } catch {
            throw LoadError.noPrograms(file)
        }
        try self.init(document: SceneDocument(folder: folder), programs: manifest, device: device)
    }

    /// A scene read already, with its programs: for tests and tools.
    public init(document: SceneDocument, programs manifest: ScenePrograms, device: any MTLDevice) throws {
        self.device = device
        self.document = document
        textures = SceneTextureStore(device: device, files: document.files)
        programs = CompiledPrograms(device: device, manifest: manifest)
        guard programs.count > 0 else { throw LoadError.noProgramCompiles }
        passes = try BasePasses(device: device)
        let corners: [Float] = [-1, 1, 0, 0, 0, 1, 1, 0, 1, 0, -1, -1, 0, 0, 1, 1, -1, 0, 1, 1]
        guard let quad = device.makeBuffer(bytes: corners, length: corners.count * 4) else { throw LoadError.noProgramCompiles }
        self.quad = quad
        preload()
        warmUp()
    }

    /// Draws the first picture once, small and offscreen, so that every
    /// pipeline is made and every mipmap generated here, while loading, and not
    /// in the surface's first frames.
    private func warmUp() {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: SceneFolder.pixelFormat, width: 64, height: 36, mipmapped: false
        )
        descriptor.usage = [.renderTarget]
        descriptor.storageMode = .private
        guard
            let target = device.makeTexture(descriptor: descriptor),
            let queue = device.makeCommandQueue(),
            let buffer = queue.makeCommandBuffer()
        else { return }
        buffer.label = "livepaper.scene-warm-up"
        draw(into: target, on: buffer, at: 0)
        buffer.commit()
        buffer.waitUntilCompleted()
        (width, height, sceneColour, targets) = (0, 0, nil, [:])
    }

    /// The output's size in pixels. The scene covers it, centred, cropping the longer way.
    public func resize(width: Int, height: Int) {
        guard width > 0, height > 0, width != self.width || height != self.height else { return }
        self.width = width
        self.height = height
        let outputAspect = Float(width) / Float(height)
        let sceneAspect = document.width / document.height
        var (left, right, bottom, top) = (Float(0), document.width, Float(0), document.height)
        if outputAspect > sceneAspect {
            let visible = document.width / outputAspect
            bottom = (document.height - visible) / 2
            top = bottom + visible
        } else {
            let visible = document.height * outputAspect
            left = (document.width - visible) / 2
            right = left + visible
        }
        projection = Self.orthographic(left: left, right: right, bottom: bottom, top: top)
        pixelsPerUnit = Float(width) / (right - left)
        targets = [:]
        sceneColour = makeTarget(width: width, height: height)
    }

    /// Encodes the picture at `time` seconds of scene time into `commandBuffer`,
    /// ending in `texture`, the drawable. Commits nothing and waits for nothing.
    public func draw(into texture: any MTLTexture, on commandBuffer: any MTLCommandBuffer, at time: Double) {
        if sceneColour == nil { resize(width: texture.width, height: texture.height) }
        guard let sceneColour else { return }
        let time = Float(time)
        followPointer(to: time)
        textures.encodePendingWork(on: commandBuffer)
        clear(sceneColour, to: document.clearColour, on: commandBuffer)
        for (index, object) in document.objects.enumerated() {
            switch object {
            case .layer(let layer) where layer.isVisible:
                switch layer.kind {
                case .image, .solid: drawImageLayer(layer, at: time, into: sceneColour, on: commandBuffer)
                case .fullscreen: drawFullscreenLayer(layer, at: time, into: sceneColour, on: commandBuffer)
                case .compose: drawComposeLayer(layer, at: time, into: sceneColour, on: commandBuffer)
                }
            case .particles(let particles) where particles.isVisible:
                drawParticles(particles, index: index, at: time, into: sceneColour, on: commandBuffer)
            default:
                break
            }
        }
        drawBloom(into: sceneColour, on: commandBuffer)
        passes.draw(sceneColour, into: texture, on: commandBuffer, .init(load: .dontCare, blending: .normal, parameters: .copy()))
    }

    public func makeSoundtrack() -> SceneSoundtrack? {
        SceneSoundtrack(document: document)
    }

    public func pointerMoved(to position: SIMD2<Float>) {
        pointerTarget = simd_clamp(position, .zero, .one)
    }

    // MARK: The pointer

    /// Eases the pointer the scene sees towards the real one, by the scene's
    /// `cameraparallaxdelay`, a quarter of it in seconds being the time taken
    /// to go most of the way (inferred: 2.0 reads as a slow, heavy follow).
    private func followPointer(to time: Float) {
        defer { lastTime = time }
        guard let last = lastTime, time > last else {
            if lastTime == nil { pointer = pointerTarget }
            return
        }
        let delay = max(document.float(document.general["cameraparallaxdelay"], 0.1) / 4, 0.01)
        pointer += (pointerTarget - pointer) * (1 - exp(-(time - last) / delay))
    }

    /// How far camera parallax moves an object: against the pointer's offset
    /// from the middle, by the scene's `cameraparallaxamount` and the object's
    /// `parallaxDepth`, in scene units, so that at the edge of the display an
    /// object of depth 1 moves by the amount times half the scene. Inferred,
    /// not measured against Wallpaper Engine.
    func parallaxOffset(_ transform: SceneTransform) -> SIMD3<Float> {
        guard document.bool(document.general["cameraparallax"], false) else { return .zero }
        let amount = document.float(document.general["cameraparallaxamount"], 0.5)
        let size = SIMD2(document.width, document.height)
        let away = SIMD2(-(pointer.x - 0.5), pointer.y - 0.5) * size * amount * transform.parallaxDepth
        return SIMD3(away.x, away.y, 0)
    }

    // MARK: Helpers

    func note(_ text: String) {
        if noted.insert(text).inserted { noteList.append(text) }
    }

    static func orthographic(left: Float, right: Float, bottom: Float, top: Float) -> simd_float4x4 {
        simd_float4x4(columns: (
            SIMD4(2 / (right - left), 0, 0, 0), SIMD4(0, 2 / (top - bottom), 0, 0), SIMD4(0, 0, 1, 0),
            SIMD4(-(right + left) / (right - left), -(top + bottom) / (top - bottom), 0.5, 1)
        ))
    }

    /// Scene units to clip space for an object: to its origin, turned about z, scaled.
    func modelViewProjection(_ transform: SceneTransform, halfSize: SIMD2<Float>) -> simd_float4x4 {
        var translation = matrix_identity_float4x4
        translation.columns.3 = SIMD4(transform.origin.x, transform.origin.y, 0, 1)
        let (cosine, sine) = (cos(transform.angles.z), sin(transform.angles.z))
        let rotation = simd_float4x4(columns: (
            SIMD4(cosine, sine, 0, 0), SIMD4(-sine, cosine, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)
        ))
        let scale = simd_float4x4(diagonal: SIMD4(halfSize.x * transform.scale.x, halfSize.y * transform.scale.y, 1, 1))
        return projection * translation * rotation * scale
    }

    func makeTarget(width: Int, height: Int) -> any MTLTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: max(1, width), height: max(1, height), mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .private
        return device.makeTexture(descriptor: descriptor)!
    }

    /// A named render target that lives as long as the output's size does.
    func target(_ key: String, width: Int, height: Int) -> any MTLTexture {
        let (width, height) = (min(max(1, width), 8192), min(max(1, height), 8192))
        if let target = targets[key], target.width == width, target.height == height { return target }
        let target = makeTarget(width: width, height: height)
        targets[key] = target
        return target
    }

    func clear(_ texture: any MTLTexture, to colour: SIMD3<Float>, on commandBuffer: any MTLCommandBuffer) {
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        let (red, green, blue) = (Double(colour.x), Double(colour.y), Double(colour.z))
        pass.colorAttachments[0].clearColor = MTLClearColor(red: red, green: green, blue: blue, alpha: 1)
        pass.colorAttachments[0].storeAction = .store
        commandBuffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
    }

    func copy(_ source: any MTLTexture, to target: any MTLTexture, on commandBuffer: any MTLCommandBuffer) {
        guard source.width == target.width, source.height == target.height else {
            passes.draw(source, into: target, on: commandBuffer, .init(load: .dontCare, blending: .normal, parameters: .copy()))
            return
        }
        guard let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        blit.copy(from: source, to: target)
        blit.endEncoding()
    }
}

// MARK: Loading

extension WallpaperEngineScene {
    /// Uploads every texture the scene names and reads its puppets and particle
    /// systems now, so that drawing never decodes or parses.
    private func preload() {
        for (index, object) in document.objects.enumerated() {
            preload(object, at: index)
        }
        for entry in programs.manifest.programs.values {
            for name in entry.samplerDefaults.values where !name.hasPrefix("_rt_") { _ = textures.texture(named: name) }
        }
        for problem in document.problems { note(problem) }
    }

    /// One of the scene's objects, the `index`th, readied for drawing, or noted when it cannot be drawn.
    private func preload(_ object: SceneObject, at index: Int) {
        switch object {
        case .layer(let layer):
            preload(layer)
        case .particles(let particles):
            preload(particles, at: index)
        case .sound(let sound):
            if !sound.files.contains(where: document.files.contains) {
                note("sound \(sound.files.joined(separator: ", ")) is missing")
            }
        case .other(_, let name, let keys):
            note("object \(name) is not drawn (\(keys.joined(separator: ", ")))")
        }
    }

    /// A layer's texture, the textures its effects name other than render targets, and its puppet.
    private func preload(_ layer: SceneLayer) {
        if let name = layer.material?.textures.first ?? nil { _ = textures.texture(named: name) }
        for effect in layer.effects {
            for pass in effect.passes {
                for case let name? in pass.material?.textures ?? [] where !name.hasPrefix("_rt_") {
                    _ = textures.texture(named: name)
                }
            }
        }
        guard let path = layer.puppet else { return }
        do {
            puppets[layer.id] = try PuppetMesh(ScenePuppet(data: document.files.data(path) ?? Data()), device: device)
        } catch {
            note("puppet \(path) cannot be read: drawn flat")
        }
    }

    /// A particle object's systems, kept by the object's `index` in the scene, and their textures.
    private func preload(_ particles: SceneParticles, at index: Int) {
        do {
            let group = try ParticleGroup(particles, in: document)
            particleGroups[index] = group
            let unsupported = Set(group.unsupported)
            if !unsupported.isEmpty {
                note("particle features not drawn: \(unsupported.sorted().joined(separator: ", ")) (\(particles.file))")
            }
            for part in group.parts {
                if let name = part.material.textures.first ?? nil { _ = textures.texture(named: name) }
            }
        } catch {
            note("particles \(particles.file) cannot be read")
        }
    }
}
