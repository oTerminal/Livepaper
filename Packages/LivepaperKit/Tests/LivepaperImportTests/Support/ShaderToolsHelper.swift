import Foundation
import Metal
import Testing
import LivepaperImport

/// The shader tools built by `Helpers/shader-tools/build.sh`, or those in the
/// folder `LIVEPAPER_SHADER_TOOLS` names.
///
/// A checkout that has not built them skips the tests that need them. CI sets
/// `LIVEPAPER_REQUIRE_SHADER_TOOLS`, which turns the skip into a failure.
enum ShaderToolsHelper {
    static let tools: ShaderTools? = {
        let environment = ProcessInfo.processInfo.environment
        let repository = URL(filePath: #filePath).deletingLastPathComponent()
            .appending(path: "../../../../..", directoryHint: .isDirectory).standardizedFileURL
        let folder = environment["LIVEPAPER_SHADER_TOOLS"].map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? repository.appending(path: "Helpers/shader-tools/out", directoryHint: .isDirectory)
        return ShaderTools.locate(bundled: folder.appending(path: "glslang"), folder.appending(path: "spirv-cross"))
    }()

    static let isRequired = ProcessInfo.processInfo.environment["LIVEPAPER_REQUIRE_SHADER_TOOLS"] == "1"
    static let shouldRun = tools != nil || isRequired

    static func required() throws -> ShaderTools {
        try #require(tools, "the shader tools are not built: run `make shader-tools`")
    }
}

/// A GPU to compile Metal with, when the machine has one.
enum GPU {
    static let device: (any MTLDevice)? = MTLCreateSystemDefaultDevice()

    /// Compiles the source, or says why it does not.
    static func compile(_ msl: String, on device: any MTLDevice) -> String? {
        do {
            _ = try device.makeLibrary(source: msl, options: nil)
            return nil
        } catch {
            return "\(error)"
        }
    }
}
