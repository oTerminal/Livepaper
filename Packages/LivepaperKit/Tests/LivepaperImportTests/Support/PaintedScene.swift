import Foundation
import Metal
import Synchronization
import LivepaperScene

/// A drawing that paints the whole picture one colour, its red the scene time over 20 s,
/// and remembers, by the folder it was made for, the sizes it was given and the times it
/// drew at. It reads nothing from the folder: a scene's poster drawn without a Workshop file.
final class PaintedScene: SceneDrawing {
    struct Calls: Equatable, Sendable {
        var sizes: [[Int]] = []
        var times: [Double] = []
    }

    private static let calls = Mutex<[String: Calls]>([:])
    private let folder: String

    required init(folder: URL, device: any MTLDevice) throws {
        self.folder = folder.standardizedFileURL.path
    }

    /// What the drawings made for `folder` were asked to do.
    static func calls(for folder: URL) -> Calls {
        calls.withLock { $0[folder.standardizedFileURL.path] ?? Calls() }
    }

    /// The picture at `time` seconds, red, green and blue from 0 to 255.
    static func colour(at time: Double) -> [Int] {
        [Int((min(time / 20, 1) * 255).rounded()), 64, 191]
    }

    func resize(width: Int, height: Int) {
        Self.calls.withLock { $0[folder, default: Calls()].sizes.append([width, height]) }
    }

    func draw(into texture: any MTLTexture, on commandBuffer: any MTLCommandBuffer, at time: Double) {
        Self.calls.withLock { $0[folder, default: Calls()].times.append(time) }
        let colour = Self.colour(at: time).map { Double($0) / 255 }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: colour[0], green: colour[1], blue: colour[2], alpha: 1)
        commandBuffer.makeRenderCommandEncoder(descriptor: pass)?.endEncoding()
    }
}

/// A drawing that refuses every scene, as `WallpaperEngineScene` refuses one that has no programs yet.
final class UnpreparedScene: SceneDrawing {
    struct NoPrograms: LocalizedError {
        var errorDescription: String? { "it has no programs" }
    }

    required init(folder: URL, device: any MTLDevice) throws {
        throw NoPrograms()
    }

    func draw(into texture: any MTLTexture, on commandBuffer: any MTLCommandBuffer, at time: Double) {}
    func resize(width: Int, height: Int) {}
}
