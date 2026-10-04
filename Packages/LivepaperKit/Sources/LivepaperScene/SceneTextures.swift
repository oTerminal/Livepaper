import Foundation
import Metal

/// A sheet of frames in a grid, left to right then top to bottom, that particles pick from (`ParticleTextures`).
struct FrameGrid {
    var columns = 1
    var rows = 1
    var count = 1
}

/// A texture on the GPU: one Metal texture per image, since a sprite sheet can span several.
final class LoadedTexture {
    let textures: [any MTLTexture]
    /// What `g_TextureNResolution` carries: the texture's width and height, then its image's.
    let resolution: SIMD4<Float>
    /// A sprite sheet's frames, played over time; empty for a still.
    let frames: [SceneTexture.Frame]
    /// A sheet of frames that particles pick from; one frame for any other texture.
    let grid: FrameGrid
    let isPointFiltered: Bool
    let clamps: Bool

    init(
        textures: [any MTLTexture], resolution: SIMD4<Float>, frames: [SceneTexture.Frame] = [],
        grid: FrameGrid = FrameGrid(), isPointFiltered: Bool = false, clamps: Bool = true
    ) {
        self.textures = textures
        self.resolution = resolution
        self.frames = frames
        self.grid = grid
        self.isPointFiltered = isPointFiltered
        self.clamps = clamps
    }

    private var duration: Float { frames.reduce(0) { $0 + $1.seconds } }

    /// The image and the rectangle in it (origin and size, in UV) to draw at
    /// `time`: the sprite sheet's frame then, or the image inside its padded texture.
    func frame(at time: Float) -> (texture: any MTLTexture, rect: SIMD4<Float>) {
        let duration = duration
        guard !frames.isEmpty, duration > 0 else {
            return (textures[0], SIMD4(0, 0, resolution.z / max(resolution.x, 1), resolution.w / max(resolution.y, 1)))
        }
        var remaining = time.truncatingRemainder(dividingBy: duration)
        var chosen = frames[frames.count - 1]
        for frame in frames {
            if remaining < frame.seconds {
                chosen = frame
                break
            }
            remaining -= frame.seconds
        }
        let texture = textures[min(max(chosen.image, 0), textures.count - 1)]
        let (width, height) = (Float(texture.width), Float(texture.height))
        return (texture, SIMD4(chosen.x / width, chosen.y / height, chosen.across.x / width, chosen.down.y / height))
    }
}

/// Loads a scene's textures from its package, all at load, so drawing never
/// decodes; and stands in, with our own pictures, for the ones that ship with
/// Wallpaper Engine itself (`ParticleTextures`).
final class SceneTextureStore {
    private let device: any MTLDevice
    private let files: SceneFiles
    private var cache: [String: LoadedTexture?] = [:]
    private var samplers: [String: any MTLSamplerState] = [:]
    /// Mipmaps to make in the next command buffer, since loading has no queue of its own.
    private var pendingMipmaps: [any MTLTexture] = []
    /// What was stood in for or could not be read, once each, for the log.
    private(set) var notes: [String] = []

    private(set) lazy var white: LoadedTexture = solid([255, 255, 255, 255])

    init(device: any MTLDevice, files: SceneFiles) {
        self.device = device
        self.files = files
    }

    func texture(named name: String) -> LoadedTexture? {
        if let loaded = cache[name] { return loaded }
        var loaded: LoadedTexture?
        if let data = files.data(SceneFiles.texturePath(name)) {
            do {
                loaded = try upload(SceneTexture(data: data))
            } catch {
                notes.append("texture \(name) cannot be read")
            }
        } else if let picture = ParticleTextures.picture(for: name) {
            loaded = upload(picture)
            notes.append("texture \(name) is Wallpaper Engine's own: drawn with our stand-in")
        } else {
            notes.append("texture \(name) is missing")
        }
        cache[name] = loaded
        return loaded
    }

    func encodePendingWork(on commandBuffer: any MTLCommandBuffer) {
        guard !pendingMipmaps.isEmpty, let blit = commandBuffer.makeBlitCommandEncoder() else { return }
        for texture in pendingMipmaps { blit.generateMipmaps(for: texture) }
        blit.endEncoding()
        pendingMipmaps = []
    }

    func sampler(pointFiltered: Bool, clamps: Bool) -> any MTLSamplerState {
        let key = "\(pointFiltered)\(clamps)"
        if let sampler = samplers[key] { return sampler }
        let descriptor = MTLSamplerDescriptor()
        descriptor.minFilter = pointFiltered ? .nearest : .linear
        descriptor.magFilter = pointFiltered ? .nearest : .linear
        descriptor.mipFilter = pointFiltered ? .notMipmapped : .linear
        descriptor.sAddressMode = clamps ? .clampToEdge : .repeat
        descriptor.tAddressMode = clamps ? .clampToEdge : .repeat
        let sampler = device.makeSamplerState(descriptor: descriptor)!
        samplers[key] = sampler
        return sampler
    }

    private func upload(_ texture: SceneTexture) throws -> LoadedTexture {
        guard !texture.isVideo else { throw SceneReadError.malformedScene }
        var textures: [any MTLTexture] = []
        var resolution = SIMD4<Float>(1, 1, 1, 1)
        for image in texture.images.indices {
            let pixels = try texture.pixels(image: image)
            let format: MTLPixelFormat = switch pixels.bytesPerPixel {
            case 1: .r8Unorm
            case 2: .rg8Unorm
            default: .rgba8Unorm
            }
            let mipmapped = texture.images[image].count > 1
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(
                pixelFormat: format, width: pixels.width, height: pixels.height, mipmapped: mipmapped
            )
            descriptor.usage = [.shaderRead]
            descriptor.storageMode = .shared
            guard let made = device.makeTexture(descriptor: descriptor) else { throw SceneReadError.malformedScene }
            pixels.bytes.withUnsafeBytes { raw in
                guard let base = raw.baseAddress else { return }
                made.replace(
                    region: MTLRegionMake2D(0, 0, pixels.width, pixels.height), mipmapLevel: 0,
                    withBytes: base, bytesPerRow: pixels.width * pixels.bytesPerPixel
                )
            }
            if mipmapped { pendingMipmaps.append(made) }
            textures.append(made)
            if image == 0 {
                resolution = SIMD4(
                    Float(pixels.width), Float(pixels.height),
                    Float(min(texture.imageWidth, pixels.width)), Float(min(texture.imageHeight, pixels.height))
                )
            }
        }
        guard !textures.isEmpty else { throw SceneReadError.malformedScene }
        return LoadedTexture(
            textures: textures, resolution: resolution, frames: texture.frames,
            isPointFiltered: texture.isPointFiltered, clamps: texture.clamps
        )
    }

    private func upload(_ picture: ParticleTextures.Picture) -> LoadedTexture? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm, width: picture.width, height: picture.height, mipmapped: true
        )
        descriptor.usage = [.shaderRead]
        descriptor.storageMode = .shared
        guard let made = device.makeTexture(descriptor: descriptor) else { return nil }
        made.replace(
            region: MTLRegionMake2D(0, 0, picture.width, picture.height), mipmapLevel: 0,
            withBytes: picture.pixels, bytesPerRow: picture.width * 4
        )
        pendingMipmaps.append(made)
        let size = SIMD4(Float(picture.width), Float(picture.height), Float(picture.width), Float(picture.height))
        return LoadedTexture(
            textures: [made], resolution: size, grid: FrameGrid(columns: picture.columns, rows: picture.rows, count: picture.frameCount),
            clamps: picture.clamps
        )
    }

    private func solid(_ rgba: [UInt8]) -> LoadedTexture {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: 1, height: 1, mipmapped: false)
        descriptor.storageMode = .shared
        let made = device.makeTexture(descriptor: descriptor)!
        made.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: rgba, bytesPerRow: 4)
        return LoadedTexture(textures: [made], resolution: SIMD4(1, 1, 1, 1))
    }
}
