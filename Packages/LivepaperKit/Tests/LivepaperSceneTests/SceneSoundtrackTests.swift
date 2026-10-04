import Foundation
import Testing
@testable import LivepaperScene
import LivepaperTestSupport

/// A scene's sounds: silent and not even decoded while the wallpaper is muted,
/// as it is at first; at the scene's volume times the wallpaper's once heard;
/// paused and stopped with the scene. On a sound made in the test, of silence,
/// so that running the tests is never heard.
@MainActor
struct SceneSoundtrackTests {
    /// Half a second of silence, as a WAV file.
    static func silence() -> Data {
        let rate = 8000
        let samples = [Int16](repeating: 0, count: rate / 2)
        var data = Data("RIFF".utf8)
        func word(_ value: UInt32) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        func half(_ value: UInt16) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        word(UInt32(36 + samples.count * 2))
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        word(16)
        half(1)
        half(1)
        word(UInt32(rate))
        word(UInt32(rate * 2))
        half(2)
        half(16)
        data.append(contentsOf: Array("data".utf8))
        word(UInt32(samples.count * 2))
        for sample in samples { withUnsafeBytes(of: sample.littleEndian) { data.append(contentsOf: $0) } }
        return data
    }

    static func document(sounds: [String]) throws -> SceneDocument {
        let entries = [
            SyntheticScene.Entry("scene.json", json: SyntheticScene.sceneJSON(width: 64, height: 32, layers: sounds)),
            SyntheticScene.Entry("sounds/rain.wav", silence()),
        ]
        return try SceneDocument(files: SceneFiles(package: ScenePackage(data: SyntheticScene.package(entries))))
    }

    @Test func `is silent and decodes nothing while the wallpaper is muted`() throws {
        let soundtrack = try #require(SceneSoundtrack(document: Self.document(sounds: [
            #"{"id": 1, "name": "rain", "sound": ["sounds/rain.wav"], "volume": 0.5, "playbackmode": "loop"}"#,
        ])))

        soundtrack.play()

        #expect(soundtrack.playing.isEmpty)
        #expect(!soundtrack.hasPlayers)
    }

    @Test func `plays at the scene's volume times the wallpaper's, and pauses and stops with the scene`() throws {
        let soundtrack = try #require(SceneSoundtrack(document: Self.document(sounds: [
            #"{"id": 1, "name": "rain", "sound": ["sounds/rain.wav"], "volume": 0.5, "playbackmode": "loop"}"#,
        ])))

        soundtrack.setVolume(0.4)
        soundtrack.play()
        #expect(soundtrack.playing == ["sounds/rain.wav": 0.2])

        soundtrack.setVolume(1)
        #expect(soundtrack.playing == ["sounds/rain.wav": 0.5])

        soundtrack.pause()
        #expect(soundtrack.playing.isEmpty)
        #expect(soundtrack.hasPlayers)

        soundtrack.play()
        soundtrack.setVolume(0)
        #expect(soundtrack.playing.isEmpty)

        soundtrack.stop()
        #expect(!soundtrack.hasPlayers)
    }

    @Test func `leaves out a sound that starts silent or is not visible, and a scene with none has no soundtrack`() throws {
        #expect(try SceneSoundtrack(document: Self.document(sounds: [
            #"{"id": 1, "name": "a", "sound": ["sounds/rain.wav"], "startsilent": true}"#,
            #"{"id": 2, "name": "b", "sound": ["sounds/rain.wav"], "visible": false}"#,
        ])) == nil)
        #expect(try SceneSoundtrack(document: Self.document(sounds: [])) == nil)
    }
}
